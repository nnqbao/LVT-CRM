import Foundation

enum DutyListTab: Int, CaseIterable, Equatable {
    case upcoming
    case ongoing
    case past

    var systemImage: String {
        switch self {
        case .upcoming: return "clock"
        case .ongoing: return "play.circle"
        case .past: return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .upcoming: return "Sắp diễn ra"
        case .ongoing: return "Đang diễn ra"
        case .past: return "Đã diễn ra"
        }
    }
}

enum DutyListRules {
    static func displayTitle(_ duty: DutyItem) -> String {
        let title = duty.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let content = duty.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? "Công tác" : content
    }

    static func isCreatedBy(_ duty: DutyItem, userId: String) -> Bool {
        !userId.isEmpty && duty.createdBy == userId
    }

    static func isAssigned(_ duty: DutyItem) -> Bool { duty.isMine }

    static func split(_ list: [DutyItem], userId: String, includeManagedOthers: Bool, leftoverInMine: Bool) -> (mine: [DutyItem], created: [DutyItem]) {
        let mine = list.filter(isAssigned)
        let created = list.filter { isCreatedBy($0, userId: userId) }
        guard includeManagedOthers else { return (mine, created) }
        let leftovers = list.filter { !isAssigned($0) && !isCreatedBy($0, userId: userId) }
        return leftoverInMine ? (mine + leftovers, created) : (mine, created + leftovers)
    }

    static func isPast(_ duty: DutyItem) -> Bool { duty.isOverdue }

    static func tab(for duty: DutyItem) -> DutyListTab {
        if isPast(duty) { return .past }
        if duty.isOngoing { return .ongoing }
        return .upcoming
    }

    static func filterBySearch(_ list: [DutyItem], search: ListSearchValues) -> [DutyItem] {
        let query = ListSearch.normalize(search.query)
        let department = ListSearch.normalize(search.department)
        let person = ListSearch.normalize(search.person)
        let location = ListSearch.normalize(search.location)
        let dateFrom = search.dateFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateTo = search.dateTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty && department.isEmpty && person.isEmpty && location.isEmpty && dateFrom.isEmpty && dateTo.isEmpty {
            return list
        }
        return list.filter { duty in
            let queryText = [duty.title, duty.content].joined(separator: " ")
            let departmentText = duty.departmentNames.joined(separator: " ")
            let personText = (duty.participantNames + duty.departmentParticipants.flatMap(\.participantNames) + [duty.otherParticipants])
                .joined(separator: " ")
            let locationText = (duty.locationNames + [duty.locationText]).joined(separator: " ")
            if !query.isEmpty && !ListSearch.includes(queryText, query) { return false }
            if !ListSearch.includes(departmentText, department) { return false }
            if !ListSearch.includes(personText, person) { return false }
            if !ListSearch.includes(locationText, location) { return false }
            return ListSearch.dateRangeOverlaps(start: duty.startDate, end: duty.endDate, dateFrom: dateFrom, dateTo: dateTo)
        }
    }

    static func filter(_ list: [DutyItem], tab: DutyListTab) -> [DutyItem] {
        let byStart = { (lhs: DutyItem, rhs: DutyItem) in
            "\(lhs.startDate)T\(lhs.startTime)" < "\(rhs.startDate)T\(rhs.startTime)"
        }
        switch tab {
        case .past:
            return list.filter(isPast).sorted {
                let lhs = "\($0.endDate)T\($0.endTime)"
                let rhs = "\($1.endDate)T\($1.endTime)"
                if lhs != rhs { return lhs < rhs }
                return byStart($0, $1)
            }
        case .ongoing:
            return list.filter(\.isOngoing).sorted(by: byStart)
        case .upcoming:
            return list.filter { !isPast($0) && !$0.isOngoing }.sorted(by: byStart)
        }
    }
}

@MainActor
final class DutiesViewModel {
    private(set) var loading = true
    private(set) var refreshing = false
    private(set) var error: String?
    private(set) var actionError: String?
    private(set) var attendanceConfirmationEnabled = false
    private(set) var duties: [DutyItem] = []
    private(set) var busyDutyId: String?
    private(set) var canCreate = false
    private(set) var isAdmin = false
    private(set) var canViewAll = false
    var mineTab: DutyListTab = .upcoming {
        didSet { if mineTab != oldValue { notifyChange() } }
    }
    var createdTab: DutyListTab = .upcoming {
        didSet { if createdTab != oldValue { notifyChange() } }
    }
    var search = ListSearchValues() {
        didSet { if search != oldValue { notifyChange() } }
    }
    var onChange: (() -> Void)?

    var lists: (mine: [DutyItem], created: [DutyItem]) {
        DutyListRules.split(
            duties,
            userId: currentUserId,
            includeManagedOthers: isAdmin || canViewAll,
            leftoverInMine: !isAdmin
        )
    }

    var tabMine: [DutyItem] { DutyListRules.filter(lists.mine, tab: mineTab) }
    var tabCreated: [DutyItem] { DutyListRules.filter(lists.created, tab: createdTab) }
    var visibleMine: [DutyItem] { DutyListRules.filterBySearch(tabMine, search: search) }
    var visibleCreated: [DutyItem] { DutyListRules.filterBySearch(tabCreated, search: search) }
    var showCreatedSection: Bool { canCreate || !lists.created.isEmpty }
    var mineSearchEmpty: Bool { !tabMine.isEmpty && visibleMine.isEmpty }
    var createdSearchEmpty: Bool { !tabCreated.isEmpty && visibleCreated.isEmpty }

    private let repository: DutiesRepository
    private let currentUserId: String
    private var operationBusy = false
    private var refreshPending = false
    private var task: Task<Void, Never>?

    init(repository: DutiesRepository, currentUserId: String) {
        self.repository = repository
        self.currentUserId = currentUserId
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
        notifyChange()
        task = Task { [weak self] in
            guard let self else { return }
            defer { releaseOperation() }
            do {
                try await loadSnapshot()
            } catch is CancellationError {
                return
            } catch {
                self.loading = false
                self.refreshing = false
                self.error = errorMessage(error)
                self.notifyChange()
            }
        }
    }

    func setAttendance(dutyId: String, status: String) {
        guard busyDutyId == nil else { return }
        busyDutyId = dutyId
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
                if busyDutyId == dutyId { busyDutyId = nil }
                releaseOperation()
            }
            do {
                try await repository.setAttendance(dutyId: dutyId, status: status)
                duties = duties.map { duty in
                    guard duty.id == dutyId else { return duty }
                    var updated = duty
                    updated.myStatus = status
                    updated.canMarkAttendance = false
                    return updated
                }
                notifyChange()
                do {
                    try await loadSnapshot()
                } catch {
                    actionError = "Đã lưu xác nhận, nhưng chưa tải lại được danh sách. Hãy làm mới."
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

    func duty(id: String) -> DutyItem? {
        duties.first { $0.id == id }
    }

    func canMark(_ duty: DutyItem) -> Bool {
        attendanceConfirmationEnabled && duty.isMine && duty.canMarkAttendance
    }

    private func loadSnapshot() async throws {
        let snapshot = try await repository.listMine()
        attendanceConfirmationEnabled = snapshot.attendanceConfirmationEnabled
        duties = snapshot.duties
        canCreate = snapshot.canCreate
        isAdmin = snapshot.isAdmin
        canViewAll = snapshot.canViewAll
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

    private func errorMessage(_ error: Error) -> String {
        (error as? ConvexException)?.message ?? ConvexHttpClient.humanize(error.localizedDescription)
    }

    private func notifyChange() {
        onChange?()
    }
}
