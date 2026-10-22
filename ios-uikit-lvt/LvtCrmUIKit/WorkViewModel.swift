import Foundation

enum WorkListTab: Int, CaseIterable, Equatable {
    case todo
    case pendingReview
    case overdue
    case completed

    var title: String {
        switch self {
        case .todo: return "Việc cần làm"
        case .pendingReview: return "Đang chờ duyệt"
        case .overdue: return "Quá hạn"
        case .completed: return "Đã duyệt hoàn thành"
        }
    }
}

enum WorkDashboardFilter: Equatable {
    case pendingApproval
    case needsExecution
}

enum WorkListRules {
    private static let completed: Set<String> = ["completed", "completed_late"]
    /// `awaiting_approval` = a document waiting for Ban giám hiệu (web PENDING_REVIEW_STATUSES).
    private static let pendingReview: Set<String> = ["pending_completion", "pending_approval", "awaiting_approval"]

    static func vietnamToday(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isTaskCompleted(_ task: WorkTaskItem) -> Bool {
        completed.contains(task.status)
    }

    static func isTaskPendingReview(_ task: WorkTaskItem) -> Bool {
        pendingReview.contains(task.status)
    }

    static func isDocumentCompleted(_ document: WorkApprovalItem) -> Bool {
        if completed.contains(WorkApprovalRules.effectiveStatus(document)) { return true }
        if WorkApprovalRules.isUnreleased(document) { return false }
        let assignmentStatuses = document.assignments.map(\.status)
        return !assignmentStatuses.isEmpty && assignmentStatuses.allSatisfy { completed.contains($0) }
    }

    static func isDocumentPendingReview(_ document: WorkApprovalItem) -> Bool {
        if pendingReview.contains(WorkApprovalRules.effectiveStatus(document)) { return true }
        if WorkApprovalRules.isUnreleased(document) { return false }
        return document.assignments.contains { pendingReview.contains($0.status) }
    }

    static func isTaskOverdue(_ task: WorkTaskItem, today: String = vietnamToday()) -> Bool {
        if isTaskCompleted(task) { return false }
        guard !task.deadline.isEmpty else { return false }
        return task.deadline < today
    }

    static func isDocumentOverdue(_ document: WorkApprovalItem, today: String = vietnamToday()) -> Bool {
        if isDocumentCompleted(document) { return false }
        var deadlines = document.assignments.map(\.deadline).filter { !$0.isEmpty }
        if deadlines.isEmpty, !document.deadline.isEmpty { deadlines = [document.deadline] }
        guard !deadlines.isEmpty else { return false }
        return deadlines.allSatisfy { $0 < today }
    }

    static func isTaskPast(_ task: WorkTaskItem, today: String = vietnamToday()) -> Bool {
        if isTaskCompleted(task) { return true }
        return isTaskOverdue(task, today: today)
    }

    static func isDocumentPast(_ document: WorkApprovalItem, today: String = vietnamToday()) -> Bool {
        if isDocumentCompleted(document) { return true }
        return isDocumentOverdue(document, today: today)
    }

    static func filterTasks(_ list: [WorkTaskItem], tab: WorkListTab, today: String = vietnamToday()) -> [WorkTaskItem] {
        list.filter { self.tab(for: $0, today: today) == tab }.sorted { $0.deadline < $1.deadline }
    }

    static func filterDocuments(_ list: [WorkApprovalItem], tab: WorkListTab, today: String = vietnamToday()) -> [WorkApprovalItem] {
        list.filter { self.tab(for: $0, today: today) == tab }.sorted {
            deadlineKey($0) < deadlineKey($1)
        }
    }

    static func counts(forTasks list: [WorkTaskItem], today: String = vietnamToday()) -> [WorkListTab: Int] {
        var counts = Dictionary(uniqueKeysWithValues: WorkListTab.allCases.map { ($0, 0) })
        for task in list {
            let tab = tab(for: task, today: today)
            counts[tab, default: 0] += 1
        }
        return counts
    }

    static func counts(forDocuments list: [WorkApprovalItem], today: String = vietnamToday()) -> [WorkListTab: Int] {
        var counts = Dictionary(uniqueKeysWithValues: WorkListTab.allCases.map { ($0, 0) })
        for document in list {
            let tab = tab(for: document, today: today)
            counts[tab, default: 0] += 1
        }
        return counts
    }

    static func tab(for task: WorkTaskItem, today: String = vietnamToday()) -> WorkListTab {
        if isTaskCompleted(task) { return .completed }
        if isTaskPendingReview(task) { return .pendingReview }
        if isTaskOverdue(task, today: today) { return .overdue }
        return .todo
    }

    static func tab(for document: WorkApprovalItem, today: String = vietnamToday()) -> WorkListTab {
        if isDocumentCompleted(document) { return .completed }
        if isDocumentPendingReview(document) { return .pendingReview }
        if isDocumentOverdue(document, today: today) { return .overdue }
        return .todo
    }

    static func filterTasksBySearch(_ list: [WorkTaskItem], search: ListSearchValues) -> [WorkTaskItem] {
        let query = ListSearch.normalize(search.query)
        let department = ListSearch.normalize(search.department)
        let person = ListSearch.normalize(search.person)
        let dateFrom = search.dateFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTo = search.dateTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty && department.isEmpty && person.isEmpty && dateFrom.isEmpty && dateTo.isEmpty {
            return list
        }
        return list.filter { task in
            let queryText = [task.title, task.documentTitle, task.fileName, task.documentContent].joined(separator: " ")
            if !query.isEmpty && !ListSearch.includes(queryText, query) { return false }
            if !ListSearch.includes(task.departmentName, department) { return false }
            if !ListSearch.includes(task.memberNames.joined(separator: " "), person) { return false }
            return ListSearch.anyDate([task.deadline], dateFrom: dateFrom, dateTo: dateTo)
        }
    }

    static func filterDocumentsBySearch(_ list: [WorkApprovalItem], search: ListSearchValues) -> [WorkApprovalItem] {
        let query = ListSearch.normalize(search.query)
        let department = ListSearch.normalize(search.department)
        let person = ListSearch.normalize(search.person)
        let dateFrom = search.dateFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTo = search.dateTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty && department.isEmpty && person.isEmpty && dateFrom.isEmpty && dateTo.isEmpty {
            return list
        }
        return list.filter { document in
            let queryText = ([document.title, document.fileName, document.content] + document.assignments.map(\.content)).joined(separator: " ")
            let departmentText = document.assignments.map(\.departmentName).joined(separator: " ")
            let personText = document.assignments.flatMap { $0.members.map(\.name) }.joined(separator: " ")
            var deadlines = document.assignments.map(\.deadline).filter { !$0.isEmpty }
            if deadlines.isEmpty, !document.deadline.isEmpty { deadlines = [document.deadline] }
            if !query.isEmpty && !ListSearch.includes(queryText, query) { return false }
            if !ListSearch.includes(departmentText, department) { return false }
            if !ListSearch.includes(personText, person) { return false }
            return ListSearch.anyDate(deadlines, dateFrom: dateFrom, dateTo: dateTo)
        }
    }

    private static func deadlineKey(_ document: WorkApprovalItem) -> String {
        document.assignments.map(\.deadline).filter { !$0.isEmpty }.min() ?? document.deadline
    }
}

@MainActor
final class WorkViewModel {
    private(set) var loading = true
    private(set) var refreshing = false
    private(set) var error: String?
    private(set) var actionError: String?
    private(set) var notice: String?
    private(set) var isAdmin = false
    private(set) var canCreate = false
    private(set) var isOps = false
    private(set) var documentTypes: [WorkDocumentType] = []
    private(set) var accessLevel = 0
    private(set) var tasks: [WorkTaskItem] = []
    private(set) var approvals: [WorkApprovalItem] = []
    /// Ban giám hiệu "Chờ tôi duyệt" (awaiting first, then decided in the last 30 days).
    private(set) var approvalQueue: [WorkApprovalItem] = []
    private(set) var currentUserId = ""
    private(set) var completionReviews: [WorkCompletionReviewItem] = []
    private(set) var busyTaskId: String?
    private(set) var busyApprovalId: String?
    private(set) var busyReviewId: String?
    var mineTab: WorkListTab = .todo { didSet { if mineTab != oldValue { notifyChange() } } }
    var createdTab: WorkListTab = .todo { didSet { if createdTab != oldValue { notifyChange() } } }
    var showNeedsCompletionOnly = false
    var search = ListSearchValues() { didSet { if search != oldValue { notifyChange() } } }
    var onChange: (() -> Void)?

    var awaitingApprovalCount: Int { approvalQueue.filter(\.awaitingMyDecision).count }

    var tabMine: [WorkTaskItem] {
        WorkListRules.filterTasks(tasks, tab: mineTab)
    }

    var tabCreated: [WorkApprovalItem] {
        WorkListRules.filterDocuments(approvals, tab: createdTab)
    }

    var visibleMine: [WorkTaskItem] {
        WorkListRules.filterTasksBySearch(tabMine, search: search)
    }

    var visibleCreated: [WorkApprovalItem] {
        WorkListRules.filterDocumentsBySearch(tabCreated, search: search)
    }

    var mineSearchEmpty: Bool { !tabMine.isEmpty && visibleMine.isEmpty }
    var createdSearchEmpty: Bool { !tabCreated.isEmpty && visibleCreated.isEmpty }
    var mineTabCounts: [WorkListTab: Int] {
        WorkListRules.counts(forTasks: tasks)
    }
    var createdTabCounts: [WorkListTab: Int] {
        WorkListRules.counts(forDocuments: approvals)
    }

    var visibleApprovals: [WorkApprovalItem] { visibleCreated }
    var visibleTasks: [WorkTaskItem] { visibleMine }

    private let repository: WorkRepository
    private var operationBusy = false
    private var refreshPending = false
    private var localCompletions: [String: String] = [:]
    private var task: Task<Void, Never>?

    init(repository: WorkRepository) {
        self.repository = repository
    }

    deinit { task?.cancel() }

    func refresh(initial: Bool = false) {
        if operationBusy {
            refreshPending = true
            return
        }
        operationBusy = true
        loading = initial
        refreshing = !initial
        error = nil
        actionError = nil
        notice = nil
        notifyChange()
        task = Task { [weak self] in
            guard let self else { return }
            defer { releaseOperation() }
            do {
                try await loadSnapshot()
            } catch is CancellationError {
                return
            } catch {
                loading = false
                refreshing = false
                self.error = errorMessage(error)
                notifyChange()
            }
        }
    }

    func task(id: String) -> WorkTaskItem? { tasks.first { $0.id == id } }

    func approval(focusId: String) -> WorkApprovalItem? {
        approvals.first { approval in
            approval.id == focusId || approval.assignments.contains { $0.id == focusId }
        }
    }

    func queueItem(focusId: String) -> WorkApprovalItem? {
        approvalQueue.first { $0.id == focusId }
    }

    /// Approver picker requirement for the create/edit form (UX only; the server decides).
    func approversRequired(requiresApproval: Bool, assignments: [WorkCreateAssignment]) -> Bool {
        WorkApprovalRules.approversRequired(
            requiresApproval: requiresApproval,
            assignments: assignments,
            currentUserId: currentUserId
        )
    }

    func review(focusId: String) -> WorkCompletionReviewItem? {
        completionReviews.first { $0.id == focusId || $0.workItemId == focusId }
    }

    func applyDashboardFilter(_ filter: WorkDashboardFilter) {
        switch filter {
        case .pendingApproval:
            showNeedsCompletionOnly = false
            mineTab = .pendingReview
            createdTab = .pendingReview
        case .needsExecution:
            showNeedsCompletionOnly = false
            mineTab = .todo
        }
        notifyChange()
    }

    func clearDashboardFilter() {
        showNeedsCompletionOnly = false
        mineTab = .todo
        notifyChange()
    }

    func loadFormOptions() async throws -> WorkFormOptions {
        try await repository.formOptions()
    }

    func ensureDocumentTypes() async {
        if !documentTypes.isEmpty { return }
        do {
            let options = try await repository.formOptions()
            if !options.documentTypes.isEmpty {
                documentTypes = options.documentTypes
                notifyChange()
            }
        } catch {
            // Picker shows the empty-state message if types still cannot be loaded.
        }
    }

    func submitCreate(
        title: String,
        assignments: [WorkCreateAssignment],
        fileData: Data?,
        fileName: String?,
        mimeType: String?,
        documentTypeId: String = "",
        requiresApproval: Bool = false,
        approverUserIds: [String] = []
    ) async throws {
        let hasFile = fileData != nil && fileName != nil && mimeType != nil
        if let message = WorkCreatePolicy.validate(
            title: title,
            assignments: assignments,
            hasFile: hasFile,
            documentTypeId: documentTypeId,
            approversRequired: approversRequired(requiresApproval: requiresApproval, assignments: assignments),
            approverCount: approverUserIds.count
        ) {
            throw ConvexException(code: "VALIDATION", message: message)
        }
        var evidence: WorkUploadedEvidence?
        if let fileData, let fileName, let mimeType {
            evidence = try await repository.uploadEvidence(fileData: fileData, fileName: fileName, mimeType: mimeType)
        }
        _ = try await repository.createDocument(
            title: title,
            assignments: assignments,
            evidence: evidence,
            documentTypeId: {
                let trimmed = documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }(),
            approverUserIds: approverUserIds
        )
        try await loadSnapshot()
    }

    func submitUpdate(
        documentId: String,
        title: String,
        assignments: [WorkCreateAssignment],
        fileData: Data?,
        fileName: String?,
        mimeType: String?,
        documentTypeId: String = "",
        requiresApproval: Bool = false,
        reapproval: Bool = false,
        approverUserIds: [String] = []
    ) async throws {
        let hasFile = fileData != nil && fileName != nil && mimeType != nil
        let needsApprovers = reapproval || approversRequired(requiresApproval: requiresApproval, assignments: assignments)
        if let message = WorkCreatePolicy.validate(
            title: title,
            assignments: assignments,
            hasFile: hasFile,
            documentTypeId: documentTypeId,
            approversRequired: needsApprovers,
            approverCount: approverUserIds.count
        ) {
            throw ConvexException(code: "VALIDATION", message: message)
        }
        var evidence: WorkUploadedEvidence?
        if let fileData, let fileName, let mimeType {
            evidence = try await repository.uploadEvidence(fileData: fileData, fileName: fileName, mimeType: mimeType)
        }
        let trimmedType = documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
        try await repository.updateDocument(
            documentId: documentId,
            title: title,
            assignments: assignments,
            evidence: evidence,
            documentTypeId: trimmedType.isEmpty ? nil : trimmedType,
            approverUserIds: approverUserIds
        )
        try await loadSnapshot()
        notice = needsApprovers
            ? "Đã lưu và gửi duyệt lại."
            : "Đã cập nhật công việc."
        notifyChange()
    }

    func deleteDocument(id: String) {
        guard busyApprovalId == nil else { return }
        busyApprovalId = id
        runMutation {
            do {
                try await self.repository.deleteDocument(id: id)
                self.notice = "Đã xóa công văn chưa duyệt."
            } catch {
                let fallback = (error as? ConvexException)?.message ?? error.localizedDescription
                let raw = ((error as? ConvexException)?.code ?? "") + " " + fallback
                throw ConvexException(
                    code: (error as? ConvexException)?.code ?? "DELETE_FAILED",
                    message: WorkCreatePolicy.actionError(raw: raw, deleting: true, fallback: fallback)
                )
            }
        } finish: {
            if self.busyApprovalId == id { self.busyApprovalId = nil }
        }
    }

    func complete(
        _ item: WorkTaskItem,
        qualityPercent: Int?,
        fileData: Data? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        note: String? = nil,
        documentTypeId: String? = nil
    ) {
        guard busyTaskId == nil else { return }
        busyTaskId = item.id
        runMutation {
            var evidence: WorkUploadedEvidence? = nil
            if let fileData, let fileName, let mimeType {
                evidence = try await self.repository.uploadEvidence(
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
            try await self.repository.complete(
                item: item,
                qualityPercent: qualityPercent,
                evidence: evidence,
                note: note,
                documentTypeId: documentTypeId
            )
            self.rememberLocalCompletion(item, qualityPercent: qualityPercent)
            self.tasks = self.overlayLocalCompletions(self.tasks)
        } finish: {
            if self.busyTaskId == item.id { self.busyTaskId = nil }
        }
    }

    /// Ban giám hiệu approval (confirmed in the UI; irreversible, locks edit/delete).
    func approve(_ item: WorkApprovalItem) {
        decide(item, notice: "Đã duyệt công việc.") {
            try await self.repository.approveDocument(documentId: item.id)
        }
    }

    /// Return to the creator with a required reason (only before anyone approved).
    func returnDocument(_ item: WorkApprovalItem, reason: String) {
        decide(item, notice: "Đã trả lại công việc cho người tạo.") {
            try await self.repository.returnDocument(documentId: item.id, reason: reason)
        }
    }

    private func decide(
        _ item: WorkApprovalItem,
        notice message: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        guard busyApprovalId == nil else { return }
        busyApprovalId = item.id
        runMutation {
            try await operation()
            self.notice = message
            self.approvalQueue = self.approvalQueue.map {
                guard $0.id == item.id else { return $0 }
                var updated = $0
                updated.awaitingMyDecision = false
                updated.canReject = false
                return updated
            }
        } finish: {
            if self.busyApprovalId == item.id { self.busyApprovalId = nil }
        }
    }

    func reviewCompletion(
        _ review: WorkCompletionReviewItem,
        approve: Bool,
        qualityPercent: Int? = nil,
        rejectionReason: String? = nil
    ) {
        guard busyReviewId == nil else { return }
        busyReviewId = review.id
        runMutation {
            try await self.repository.reviewCompletion(
                review: review,
                approve: approve,
                qualityPercent: qualityPercent,
                rejectionReason: rejectionReason
            )
            self.completionReviews.removeAll { $0.id == review.id }
        } finish: {
            if self.busyReviewId == review.id { self.busyReviewId = nil }
        }
    }

    func clearActionError() {
        actionError = nil
        notifyChange()
    }

    private func runMutation(
        operation: @escaping @MainActor () async throws -> Void,
        finish: @escaping @MainActor () -> Void
    ) {
        actionError = nil
        notifyChange()
        task = Task { [weak self] in
            guard let self else { return }
            while operationBusy {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
            }
            operationBusy = true
            defer {
                finish()
                releaseOperation()
            }
            do {
                try await operation()
                notifyChange()
                do {
                    try await loadSnapshot()
                } catch {
                    actionError = "Đã lưu thay đổi, nhưng chưa tải lại được danh sách. Hãy làm mới."
                    notifyChange()
                }
            } catch is CancellationError {
                return
            } catch {
                actionError = errorMessage(error)
                notifyChange()
            }
        }
    }

    private func loadSnapshot() async throws {
        let snapshot = try await repository.listMine()
        isAdmin = snapshot.isAdmin
        canCreate = snapshot.canCreate
        isOps = snapshot.isOps
        documentTypes = snapshot.documentTypes
        accessLevel = snapshot.accessLevel
        dropResolvedLocalCompletions(snapshot.tasks)
        tasks = overlayLocalCompletions(snapshot.tasks)
        approvals = snapshot.approvals
        approvalQueue = snapshot.approvalQueue
        currentUserId = snapshot.currentUserId
        completionReviews = snapshot.completionReviews
        loading = false
        refreshing = false
        notifyChange()
    }

    private func releaseOperation() {
        operationBusy = false
        if refreshPending {
            refreshPending = false
            refresh()
        } else {
            notifyChange()
        }
    }

    private func completionKey(_ item: WorkTaskItem) -> String {
        "\(item.kind.rawValue)-\(item.id)"
    }

    private func rememberLocalCompletion(_ item: WorkTaskItem, qualityPercent: Int?) {
        localCompletions[completionKey(item)] = qualityPercent == nil ? "pending_completion" : "completed"
    }

    private func dropResolvedLocalCompletions(_ tasks: [WorkTaskItem]) {
        guard !localCompletions.isEmpty else { return }
        for item in tasks where WorkListRules.isTaskPendingReview(item) || WorkListRules.isTaskCompleted(item) {
            localCompletions.removeValue(forKey: completionKey(item))
        }
    }

    private func overlayLocalCompletions(_ tasks: [WorkTaskItem]) -> [WorkTaskItem] {
        guard !localCompletions.isEmpty else { return tasks }
        return tasks.map { item in
            guard let status = localCompletions[completionKey(item)] else { return item }
            if WorkListRules.isTaskPendingReview(item) || WorkListRules.isTaskCompleted(item) {
                return item
            }
            var updated = item
            updated.status = status
            return updated
        }
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? ConvexException)?.message ?? ConvexHttpClient.humanize(error.localizedDescription)
    }

    private func notifyChange() { onChange?() }
}
