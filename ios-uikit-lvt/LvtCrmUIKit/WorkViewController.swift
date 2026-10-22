import UIKit
import QuickLook
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class WorkViewController: UITableViewController {
    private enum SectionKind {
        case feedback(String)
        case notice(String)
        case loading
        case error(String)
        case reviewBanner(Int)
        case approvals([WorkApprovalItem])
        case tasks([WorkTaskItem])
        case reviews([WorkCompletionReviewItem])
    }

    private let viewModel: WorkViewModel
    private let chatRepository: ChatRepository
    private let downloadDocument: (WorkApprovalItem) async throws -> URL
    var trailingAccessoryBarButtonItems: [UIBarButtonItem] = []
    /// Called after the bar items change, so WorkHub can mirror them on its own navigation item.
    var onBarItemsChange: (() -> Void)?
    private let searchHeader = ListSearchHeaderView()
    private var pendingFocusId: String?
    private var pendingOpenChat = false
    private var pendingUploadTask: WorkTaskItem?
    private var pendingUploadNote = ""

    private static let maxUploadFileSize = 20 * 1024 * 1024
    private static let allowedUploadExtensions: Set<String> = ["pdf", "docx", "xlsx", "xls", "png", "jpg", "jpeg"]

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    init(
        viewModel: WorkViewModel,
        chatRepository: ChatRepository,
        downloadDocument: @escaping (WorkApprovalItem) async throws -> URL
    ) {
        self.viewModel = viewModel
        self.chatRepository = chatRepository
        self.downloadDocument = downloadDocument
        super.init(style: .insetGrouped)
        title = "Công việc"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.estimatedRowHeight = 150
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(WorkItemCell.self, forCellReuseIdentifier: WorkItemCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StateCell")
        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại danh sách công việc"
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.keyboardDismissMode = .onDrag
        searchHeader.onChange = { [weak self] values in self?.viewModel.search = values }
        searchHeader.onNeedsLayout = { [weak self] in self?.sizeSearchHeader() }
        searchHeader.configure(
            values: viewModel.search,
            queryPlaceholder: "Tìm theo tên hoặc nội dung công việc",
            personPlaceholder: "Tên người được giao",
            includeLocation: false
        )
        tableView.tableHeaderView = searchHeader
        viewModel.onChange = { [weak self] in self?.render() }
        render()
        viewModel.refresh(initial: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sectionKinds.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKinds[section] {
        case .approvals(let items): return max(items.count, 1)
        case .tasks(let items): return max(items.count, 1)
        case .reviews(let items): return max(items.count, 1)
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if case .reviews = sectionKinds[section] { return "Duyệt hoàn thành" }
        return nil
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch sectionKinds[section] {
        case .tasks:
            return workSectionHeader(
                title: "Việc của tôi",
                tab: viewModel.mineTab,
                counts: viewModel.mineTabCounts,
                onChange: { [weak self] tab in
                    self?.viewModel.showNeedsCompletionOnly = false
                    self?.viewModel.mineTab = tab
                }
            )
        case .approvals:
            return workSectionHeader(
                title: "Việc tôi tạo",
                tab: viewModel.createdTab,
                counts: viewModel.createdTabCounts,
                onChange: { [weak self] tab in self?.viewModel.createdTab = tab }
            )
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch sectionKinds[section] {
        case .tasks, .approvals: return 96
        default: return UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if case .tasks = sectionKinds[section], viewModel.canCreate { return 36 }
        return 8
    }

    private func emptyCopy(tab: WorkListTab, created: Bool) -> String {
        switch tab {
        case .completed:
            return created ? "Chưa có công việc bạn tạo đã duyệt hoàn thành." : "Chưa có công việc đã duyệt hoàn thành."
        case .pendingReview:
            return created ? "Không có công việc bạn tạo đang chờ duyệt." : "Không có công việc đang chờ duyệt."
        case .overdue:
            return created ? "Chưa có công việc bạn tạo quá hạn." : "Chưa có công việc quá hạn."
        case .todo:
            return created ? "Không có việc cần làm trong các công việc bạn tạo." : "Bạn chưa có việc cần làm."
        }
    }

    private func workSectionHeader(
        title: String,
        tab: WorkListTab,
        counts: [WorkListTab: Int],
        onChange: @escaping (WorkListTab) -> Void
    ) -> UIView {
        let header = WorkTabsHeaderView()
        header.configure(title: title, tab: tab, counts: counts, onChange: onChange)
        return header
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sectionKinds[indexPath.section] {
        case .feedback(let message):
            return stateCell(indexPath, "Không thể cập nhật công việc", message, "exclamationmark.circle.fill", .systemRed)
        case .notice(let message):
            return stateCell(indexPath, message, nil, "checkmark.circle.fill", .systemGreen)
        case .loading:
            let cell = stateCell(indexPath, "Đang tải công việc…", nil, nil, .secondaryLabel)
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            spinner.accessibilityLabel = "Đang tải"
            cell.accessoryView = spinner
            return cell
        case .error(let message):
            let cell = stateCell(indexPath, "Không thể tải công việc", message, "exclamationmark.triangle.fill", .systemRed)
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityHint = "Tải lại danh sách công việc"
            return cell
        case .reviewBanner(let count):
            let cell = stateCell(
                indexPath,
                "\(count) hoàn thành chờ xác nhận",
                "Mở danh sách để đánh giá",
                "exclamationmark.bubble.fill",
                .systemOrange
            )
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            return cell
        case .approvals(let items):
            guard !items.isEmpty else {
                let detail = viewModel.createdSearchEmpty
                    ? "Không tìm thấy công việc phù hợp."
                    : emptyCopy(tab: viewModel.createdTab, created: true)
                return emptyCell(indexPath, "Việc tôi tạo", detail)
            }
            let item = items[indexPath.row]
            let cell = workCell(at: indexPath)
            cell.configureApproval(
                item,
                admin: viewModel.isAdmin,
                isOps: viewModel.isOps,
                busy: viewModel.busyApprovalId == item.id,
                focused: isFocused(approval: item),
                onChat: { [weak self] in self?.presentWorkChat(documentId: item.id, title: item.title) },
                onEdit: { [weak self] in self?.openEdit(item) },
                onDelete: { [weak self] in self?.confirmDelete(item) }
            ) { [weak self] action in
                guard let self else { return }
                if action == .detail { showDocument(item) }
                else { confirmApproval(item, approve: action == .approve) }
            }
            return cell
        case .tasks(let items):
            guard !items.isEmpty else {
                let detail: String
                if viewModel.mineSearchEmpty {
                    detail = "Không tìm thấy công việc phù hợp."
                } else if viewModel.showNeedsCompletionOnly {
                    detail = "Chưa có công việc cần thực hiện."
                } else {
                    detail = emptyCopy(tab: viewModel.mineTab, created: false)
                }
                return emptyCell(indexPath, "Việc của tôi", detail)
            }
            let item = items[indexPath.row]
            let cell = workCell(at: indexPath)
            cell.configureTask(
                item,
                busy: viewModel.busyTaskId == item.id,
                focused: pendingFocusId == item.id || pendingFocusId == item.documentId,
                onChat: item.documentId.isEmpty ? nil : { [weak self] in
                    self?.presentWorkChat(
                        documentId: item.documentId,
                        title: item.documentTitle.isEmpty ? item.title : item.documentTitle
                    )
                }
            ) { [weak self] in self?.confirmCompletion(item) }
            return cell
        case .reviews(let items):
            guard !items.isEmpty else {
                return emptyCell(indexPath, "Không có yêu cầu", "Không có hoàn thành nào chờ xác nhận.")
            }
            let item = items[indexPath.row]
            let cell = workCell(at: indexPath)
            cell.configureReview(item, busy: viewModel.busyReviewId == item.id) { [weak self] in
                self?.showReview(item)
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKinds[indexPath.section] {
        case .error:
            viewModel.refresh(initial: true)
        case .reviewBanner:
            break
        case .approvals(let items) where !items.isEmpty:
            showDocument(items[indexPath.row])
        case .tasks(let items) where !items.isEmpty:
            showTask(items[indexPath.row])
        case .reviews(let items) where !items.isEmpty:
            showReview(items[indexPath.row])
        default:
            break
        }
    }

    func focus(itemId: String, openChat: Bool = false) {
        loadViewIfNeeded()
        viewModel.showNeedsCompletionOnly = false
        pendingFocusId = itemId
        pendingOpenChat = openChat
        if let task = viewModel.tasks.first(where: { $0.id == itemId || $0.documentId == itemId }) {
            viewModel.mineTab = WorkListRules.tab(for: task)
        }
        render()
    }

    func applyDashboardFilter(_ filter: WorkDashboardFilter?) {
        loadViewIfNeeded()
        if let filter {
            viewModel.applyDashboardFilter(filter)
        } else {
            viewModel.clearDashboardFilter()
        }
        render()
        if filter == .pendingApproval {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToReviewsIfNeeded()
            }
        }
    }

    private func scrollToReviewsIfNeeded() {
        guard let section = sectionKinds.firstIndex(where: { if case .reviews = $0 { true } else { false } }) else { return }
        let rowCount = tableView.numberOfRows(inSection: section)
        guard rowCount > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
    }

    private var sectionKinds: [SectionKind] {
        var sections: [SectionKind] = []
        if let actionError = viewModel.actionError { sections.append(.feedback(actionError)) }
        if let notice = viewModel.notice { sections.append(.notice(notice)) }
        if let error = viewModel.error { return sections + [.error(error)] }
        if viewModel.loading { return sections + [.loading] }
        if viewModel.canCreate, !viewModel.completionReviews.isEmpty {
            sections.append(.reviews(viewModel.completionReviews))
        }
        sections.append(.tasks(viewModel.visibleMine))
        if viewModel.canCreate {
            sections.append(.approvals(viewModel.visibleCreated))
        }
        return sections
    }

    private func render() {
        applyTrailingBarButtonItems()
        if !viewModel.refreshing { refreshControl?.endRefreshing() }
        searchHeader.configure(
            values: viewModel.search,
            queryPlaceholder: "Tìm theo tên hoặc nội dung công việc",
            personPlaceholder: "Tên người được giao",
            includeLocation: false
        )
        sizeSearchHeader()
        tableView.reloadData()
        processPendingFocusIfPossible()
    }

    private func applyTrailingBarButtonItems() {
        var items = trailingAccessoryBarButtonItems
        if viewModel.canCreate {
            items.append(UIBarButtonItem(title: "Tạo", style: .done, target: self, action: #selector(openCreate)))
        }
        navigationItem.rightBarButtonItems = items.isEmpty ? nil : items
        onBarItemsChange?()
    }

    @objc private func openCreate() {
        let controller = WorkCreateViewController(viewModel: viewModel) { [weak self] in
            self?.viewModel.refresh()
        }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func openEdit(_ item: WorkApprovalItem) {
        let controller = WorkCreateViewController(viewModel: viewModel, editingWork: item) { }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func confirmDelete(_ item: WorkApprovalItem) {
        let alert = UIAlertController(
            title: "Xóa công việc \(WorkHelpers.listTitle(item))?",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteDocument(id: item.id)
        })
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeSearchHeader()
    }

    private func sizeSearchHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        searchHeader.frame.size.width = width
        searchHeader.setNeedsLayout()
        searchHeader.layoutIfNeeded()
        let height = searchHeader.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if abs(searchHeader.frame.height - height) > 0.5 {
            searchHeader.frame.size = CGSize(width: width, height: height)
            tableView.tableHeaderView = searchHeader
        }
    }

    private func processPendingFocusIfPossible() {
        guard let focusId = pendingFocusId, !viewModel.loading else { return }
        let openChat = pendingOpenChat
        if viewModel.error != nil {
            pendingFocusId = nil
            pendingOpenChat = false
            if openChat { presentWorkChat(documentId: focusId, title: "Công việc") }
            return
        }
        pendingOpenChat = false
        if let item = viewModel.approval(focusId: focusId), item.id == focusId || !openChat {
            viewModel.createdTab = WorkListRules.tab(for: item)
            scrollToApproval(item)
            pendingFocusId = nil
            DispatchQueue.main.async { [weak self] in
                self?.showDocument(item)
                if openChat {
                    self?.presentWorkChat(documentId: item.id, title: item.title)
                }
            }
        } else if let item = viewModel.tasks.first(where: { $0.id == focusId || $0.documentId == focusId }) {
            viewModel.mineTab = WorkListRules.tab(for: item)
            scrollToTask(item)
            pendingFocusId = nil
            DispatchQueue.main.async { [weak self] in
                self?.showTask(item)
                if openChat {
                    let documentId = item.documentId.isEmpty ? focusId : item.documentId
                    let title = item.documentTitle.isEmpty ? item.title : item.documentTitle
                    self?.presentWorkChat(documentId: documentId, title: title)
                }
            }
        } else if !openChat, let item = viewModel.review(focusId: focusId) {
            pendingFocusId = nil
            DispatchQueue.main.async { [weak self] in self?.showReview(item) }
        } else if openChat {
            pendingFocusId = nil
            presentWorkChat(documentId: focusId, title: "Công việc")
        } else {
            pendingFocusId = nil
            presentMissingItemAlert()
        }
    }

    private func presentWorkChat(documentId: String, title: String) {
        guard !documentId.isEmpty else { return }
        let controller = ChatViewController(
            repository: chatRepository,
            target: ChatTarget(kind: .work, entityId: documentId, title: title.isEmpty ? "Công việc" : title)
        )
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func scrollToApproval(_ item: WorkApprovalItem) {
        guard let section = sectionKinds.firstIndex(where: { if case .approvals = $0 { true } else { false } }),
              let row = viewModel.visibleApprovals.firstIndex(where: { $0.id == item.id }) else { return }
        scrollAndAnnounce(IndexPath(row: row, section: section))
    }

    private func scrollToTask(_ item: WorkTaskItem) {
        guard let section = sectionKinds.firstIndex(where: { if case .tasks = $0 { true } else { false } }),
              let row = viewModel.visibleTasks.firstIndex(where: { $0.id == item.id }) else { return }
        scrollAndAnnounce(IndexPath(row: row, section: section))
    }

    private func scrollAndAnnounce(_ indexPath: IndexPath) {
        tableView.scrollToRow(at: indexPath, at: .middle, animated: !UIAccessibility.isReduceMotionEnabled)
        UIAccessibility.post(notification: .layoutChanged, argument: tableView.cellForRow(at: indexPath))
    }

    private func isFocused(approval: WorkApprovalItem) -> Bool {
        guard let pendingFocusId else { return false }
        return approval.id == pendingFocusId || approval.assignments.contains { $0.id == pendingFocusId }
    }

    private func confirmApproval(_ item: WorkApprovalItem, approve: Bool) {
        let alert = UIAlertController(
            title: approve ? "Duyệt công văn?" : "Từ chối công văn?",
            message: "Thao tác này không thể hoàn tác.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: approve ? "Duyệt" : "Từ chối", style: approve ? .default : .destructive) { [weak self] _ in
            self?.viewModel.decideApproval(item, approve: approve)
        })
        presentFromVisibleController(alert)
    }

    private func confirmCompletion(_ item: WorkTaskItem) {
        if item.isAdmin {
            presentQualityPrompt(item)
            return
        }
        pendingUploadTask = item
        pendingUploadNote = ""
        let alert = UIAlertController(
            title: "Nộp bằng chứng hoàn thành",
            message: "Nhập nội dung gửi người giao (không bắt buộc), rồi chọn tệp bằng chứng.",
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "Nội dung gửi người giao"
            $0.accessibilityLabel = "Nội dung gửi người giao"
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { [weak self] _ in
            self?.clearPendingUpload()
        })
        alert.addAction(UIAlertAction(title: "Chọn tệp", style: .default) { [weak self, weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            self?.pendingUploadNote = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            self?.presentEvidenceSourceSheet()
        })
        presentFromVisibleController(alert)
    }

    private func presentEvidenceSourceSheet() {
        let alert = UIAlertController(
            title: "Nộp bằng chứng hoàn thành",
            message: "Chọn phương thức nộp tài liệu/hình ảnh để người tạo/cấp trên duyệt.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Chọn từ Thư viện ảnh", style: .default) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Chụp ảnh mới", style: .default) { [weak self] _ in
                self?.presentCamera()
            })
        }
        alert.addAction(UIAlertAction(title: "Chọn từ Tệp", style: .default) { [weak self] _ in
            self?.presentDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { [weak self] _ in
            self?.clearPendingUpload()
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presentFromVisibleController(alert)
    }

    private func clearPendingUpload() {
        pendingUploadTask = nil
        pendingUploadNote = ""
    }

    private func submitEvidence(item: WorkTaskItem, fileData: Data, fileName: String, mimeType: String) {
        if item.kind == .workItem {
            presentDocumentTypePicker(item: item, fileData: fileData, fileName: fileName, mimeType: mimeType)
            return
        }
        finishEvidence(item: item, fileData: fileData, fileName: fileName, mimeType: mimeType, documentTypeId: nil)
    }

    private func presentDocumentTypePicker(
        item: WorkTaskItem,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) {
        presentAfterDismiss { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.ensureDocumentTypes()
                self.showDocumentTypeSheet(
                    item: item,
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
        }
    }

    private func showDocumentTypeSheet(
        item: WorkTaskItem,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) {
        let types = viewModel.documentTypes
        guard !types.isEmpty else {
            clearPendingUpload()
            presentValidation("Chưa có loại văn bản. Liên hệ quản trị viên.")
            return
        }
        let alert = UIAlertController(
            title: "Loại văn bản",
            message: "Chọn loại cho tệp “\(fileName)”.",
            preferredStyle: .actionSheet
        )
        for type in types {
            alert.addAction(UIAlertAction(title: type.name, style: .default) { [weak self] _ in
                self?.finishEvidence(
                    item: item,
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: mimeType,
                    documentTypeId: type.id
                )
            })
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { [weak self] _ in
            self?.clearPendingUpload()
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presentationHost().present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func finishEvidence(
        item: WorkTaskItem,
        fileData: Data,
        fileName: String,
        mimeType: String,
        documentTypeId: String?
    ) {
        let note = pendingUploadNote
        clearPendingUpload()
        viewModel.complete(
            item,
            qualityPercent: nil,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            note: note.isEmpty ? nil : note,
            documentTypeId: documentTypeId
        )
    }

    private func presentPhotoPicker() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        (navigationController ?? self).present(
            picker,
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        (navigationController ?? self).present(
            picker,
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    private func presentDocumentPicker() {
        let types: [UTType] = [
            .pdf,
            .image,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        (navigationController ?? self).present(
            picker,
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    private func presentQualityPrompt(_ item: WorkTaskItem) {
        let alert = UIAlertController(title: "Phần trăm chất lượng", message: "Nhập giá trị từ 0 đến 100.", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "0–100"
            $0.text = "100"
            $0.keyboardType = .numberPad
            $0.accessibilityLabel = "Phần trăm chất lượng"
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xác nhận", style: .default) { [weak self, weak alert] _ in
            let value = Int(alert?.textFields?.first?.text ?? "") ?? -1
            guard (0...100).contains(value) else {
                self?.presentValidation("Phần trăm chất lượng phải từ 0 đến 100.")
                return
            }
            self?.viewModel.complete(item, qualityPercent: value)
        })
        presentFromVisibleController(alert)
    }

    private func showDocument(_ item: WorkApprovalItem) {
        navigationController?.pushViewController(
            WorkDocumentViewController(
                document: item,
                isOps: viewModel.isOps,
                downloadDocument: downloadDocument,
                onOpenChat: { [weak self] in
                    self?.presentWorkChat(documentId: item.id, title: item.title)
                },
                onEdit: { [weak self] in
                    self?.navigationController?.popViewController(animated: false)
                    self?.openEdit(item)
                },
                onDelete: { [weak self] in
                    self?.navigationController?.popViewController(animated: false)
                    self?.confirmDelete(item)
                }
            ),
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    private func showTask(_ item: WorkTaskItem) {
        let detail = WorkTaskDetailViewController(
            task: item,
            busy: viewModel.busyTaskId == item.id,
            downloadDocument: downloadDocument,
            onOpenChat: item.documentId.isEmpty ? nil : { [weak self] in
                self?.presentWorkChat(
                    documentId: item.documentId,
                    title: item.documentTitle.isEmpty ? item.title : item.documentTitle
                )
            }
        ) { [weak self] in
            self?.confirmCompletion(item)
        }
        navigationController?.pushViewController(detail, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func showReview(_ item: WorkCompletionReviewItem) {
        let controller = WorkReviewViewController(review: item) { [weak self] approve, quality, reason in
            self?.viewModel.reviewCompletion(item, approve: approve, qualityPercent: quality, rejectionReason: reason)
            self?.navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentValidation(_ message: String) {
        let alert = UIAlertController(title: "Thông tin chưa hợp lệ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        presentFromVisibleController(alert)
    }

    private func presentMissingItemAlert() {
        let alert = UIAlertController(
            title: "Không tìm thấy công việc",
            message: "Mục này không còn tồn tại hoặc bạn không có quyền xem.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        presentFromVisibleController(alert)
    }

    private func presentFromVisibleController(_ alert: UIAlertController) {
        presentAfterDismiss { [weak self] in
            guard let self else { return }
            self.presentationHost().present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func presentationHost() -> UIViewController {
        navigationController ?? self
    }

    private func presentAfterDismiss(_ action: @escaping () -> Void) {
        let host = presentationHost()
        if let presented = host.presentedViewController, !presented.isBeingDismissed {
            presented.dismiss(animated: true) { [weak self] in
                self?.presentAfterDismiss(action)
            }
            return
        }
        if host.presentedViewController != nil {
            DispatchQueue.main.async { [weak self] in
                self?.presentAfterDismiss(action)
            }
            return
        }
        action()
    }

    private func workCell(at indexPath: IndexPath) -> WorkItemCell {
        tableView.dequeueReusableCell(withIdentifier: WorkItemCell.reuseIdentifier, for: indexPath) as! WorkItemCell
    }

    private func emptyCell(_ indexPath: IndexPath, _ title: String, _ detail: String) -> UITableViewCell {
        stateCell(indexPath, title, detail, "tray", .secondaryLabel)
    }

    private func stateCell(
        _ indexPath: IndexPath,
        _ title: String,
        _ detail: String?,
        _ image: String?,
        _ color: UIColor
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StateCell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.accessibilityTraits = .staticText
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.secondaryText = detail
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.color = color
        content.image = image.flatMap(UIImage.init(systemName:))
        content.imageProperties.tintColor = color
        cell.contentConfiguration = content
        cell.accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: ". ")
        return cell
    }

    @objc private func refresh() { viewModel.refresh() }
}

private enum WorkCellAction { case detail, approve, reject }

private final class WorkItemCell: UITableViewCell {
    static let reuseIdentifier = "WorkItemCell"
    private let statusLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let metaLabel = UILabel()
    private let reasonLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let chatButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let lockedLabel = UILabel()
    private let manageRow = UIStackView()
    private var onChat: (() -> Void)?
    private var onEdit: (() -> Void)?
    private var onDelete: (() -> Void)?
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        metaLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        reasonLabel.font = .preferredFont(forTextStyle: .caption1)
        [statusLabel, titleLabel, detailLabel, metaLabel, reasonLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        detailLabel.textColor = .secondaryLabel
        metaLabel.textColor = .secondaryLabel
        reasonLabel.textColor = .systemRed
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.configuration = .bordered()
        let actionRow = UIStackView(arrangedSubviews: [actionButton, spinner])
        actionRow.spacing = 8
        actionRow.alignment = .center
        chatButton.configuration = .plain()
        chatButton.configuration?.title = "Trao đổi"
        chatButton.configuration?.image = UIImage(systemName: "bubble.left")
        chatButton.configuration?.imagePadding = 6
        chatButton.accessibilityLabel = "Trao đổi công việc"
        chatButton.addAction(UIAction { [weak self] _ in self?.onChat?() }, for: .touchUpInside)
        editButton.configuration = .bordered()
        editButton.configuration?.title = "Sửa"
        editButton.accessibilityLabel = "Sửa công việc"
        editButton.addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .touchUpInside)
        deleteButton.configuration = .bordered()
        deleteButton.configuration?.title = "Xóa"
        deleteButton.accessibilityLabel = "Xóa công việc"
        deleteButton.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        manageRow.axis = .horizontal
        manageRow.spacing = 8
        manageRow.addArrangedSubview(editButton)
        manageRow.addArrangedSubview(deleteButton)
        lockedLabel.font = .preferredFont(forTextStyle: .footnote)
        lockedLabel.adjustsFontForContentSizeCategory = true
        lockedLabel.textColor = .secondaryLabel
        lockedLabel.numberOfLines = 0
        lockedLabel.text = WorkCreatePolicy.lockedMessage
        let stack = UIStackView(arrangedSubviews: [statusLabel, titleLabel, detailLabel, metaLabel, reasonLabel, actionRow, chatButton, manageRow, lockedLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        actionButton.menu = nil
        actionButton.removeTarget(nil, action: nil, for: .allEvents)
        actionButton.isHidden = false
        chatButton.isHidden = true
        onChat = nil
        onEdit = nil
        onDelete = nil
        manageRow.isHidden = true
        editButton.isHidden = true
        deleteButton.isHidden = true
        lockedLabel.isHidden = true
        reasonLabel.isHidden = true
        spinner.stopAnimating()
        backgroundColor = .secondarySystemGroupedBackground
    }

    func configureApproval(
        _ item: WorkApprovalItem,
        admin: Bool,
        isOps: Bool,
        busy: Bool,
        focused: Bool,
        onChat: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        action: @escaping (WorkCellAction) -> Void
    ) {
        statusLabel.text = item.status == "pending" ? "Chờ duyệt · \(item.approvalCount)/\(item.approvalTotal)" : "\(item.status) · \(item.approvalCount)/\(item.approvalTotal)"
        statusLabel.textColor = item.status == "pending" ? .systemOrange : .systemGreen
        titleLabel.text = WorkHelpers.listTitle(item)
        detailLabel.text = WorkHelpers.listSubtitle(item)
        detailLabel.isHidden = detailLabel.text?.isEmpty != false
        metaLabel.text = "Hạn: \(item.deadline)"
        reasonLabel.isHidden = true
        backgroundColor = focused ? UIColor.systemIndigo.withAlphaComponent(0.12) : .secondarySystemGroupedBackground
        if admin {
            setButton("Xem phân công", busy: busy) { action(.detail) }
        } else if item.myDecision.isEmpty {
            actionButton.configuration = .borderedProminent()
            actionButton.setTitle("Xử lý", for: .normal)
            actionButton.showsMenuAsPrimaryAction = true
            actionButton.menu = UIMenu(children: [
                UIAction(title: "Duyệt", image: UIImage(systemName: "checkmark.circle")) { _ in action(.approve) },
                UIAction(title: "Từ chối", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in action(.reject) },
            ])
            actionButton.isEnabled = !busy
            busy ? spinner.startAnimating() : spinner.stopAnimating()
        } else {
            actionButton.isHidden = true
            statusLabel.text = item.myDecision == "approved" ? "Bạn đã duyệt" : "Bạn đã từ chối"
            statusLabel.textColor = item.myDecision == "approved" ? .systemGreen : .systemRed
        }
        setChat(onChat)
        let canEdit = WorkCreatePolicy.showsEdit(canEdit: item.canEdit, isOps: isOps)
        let canDelete = WorkCreatePolicy.showsDelete(canDelete: item.canDelete, isOps: isOps)
        self.onEdit = onEdit
        self.onDelete = onDelete
        editButton.isHidden = !canEdit
        deleteButton.isHidden = !canDelete
        editButton.isEnabled = !busy
        deleteButton.isEnabled = !busy
        manageRow.isHidden = !canEdit && !canDelete
        lockedLabel.isHidden = !WorkCreatePolicy.showsLocked(canEdit: item.canEdit, canDelete: item.canDelete, isOps: isOps)
        accessibilityLabel = [statusLabel.text, titleLabel.text, detailLabel.text, metaLabel.text, lockedLabel.isHidden ? nil : lockedLabel.text].compactMap { $0 }.joined(separator: ". ")
    }

    func configureTask(
        _ item: WorkTaskItem,
        busy: Bool,
        focused: Bool,
        onChat: (() -> Void)?,
        complete: @escaping () -> Void
    ) {
        manageRow.isHidden = true
        editButton.isHidden = true
        deleteButton.isHidden = true
        lockedLabel.isHidden = true
        statusLabel.text = WorkPresentation.status(item.status) + (item.qualityPercent.map { " · \($0)%" } ?? "")
        statusLabel.textColor = WorkPresentation.statusColor(item.status)
        titleLabel.text = item.title
        detailLabel.text = item.documentContent
        detailLabel.isHidden = item.documentContent.isEmpty
        metaLabel.text = "\(item.departmentName) · Hạn \(item.deadline)"
        if !item.rejectionReason.isEmpty {
            reasonLabel.text = "Lý do từ chối: \(item.rejectionReason)"
            reasonLabel.textColor = .systemRed
            reasonLabel.isHidden = false
        } else if !item.note.isEmpty {
            reasonLabel.text = "Nội dung đã gửi: \(item.note)"
            reasonLabel.textColor = .secondaryLabel
            reasonLabel.isHidden = false
        } else {
            reasonLabel.isHidden = true
        }
        backgroundColor = focused ? UIColor.systemIndigo.withAlphaComponent(0.12) : .secondarySystemGroupedBackground
        if WorkHelpers.needsCompletion(item.status) {
            actionButton.configuration = .borderedProminent()
            let title = item.isAdmin ? "Hoàn thành và chấm %" : "Nộp bằng chứng hoàn thành"
            setButton(title, busy: busy, action: complete)
        } else {
            actionButton.isHidden = true
        }
        setChat(onChat)
        accessibilityLabel = [statusLabel.text, titleLabel.text, detailLabel.text, metaLabel.text, reasonLabel.text].compactMap { $0 }.joined(separator: ". ")
    }

    func configureReview(_ item: WorkCompletionReviewItem, busy: Bool, review: @escaping () -> Void) {
        manageRow.isHidden = true
        editButton.isHidden = true
        deleteButton.isHidden = true
        lockedLabel.isHidden = true
        setChat(nil)
        statusLabel.text = "Chờ xác nhận"
        statusLabel.textColor = .systemOrange
        titleLabel.text = item.userName
        detailLabel.text = item.content
        detailLabel.isHidden = false
        metaLabel.text = "\(item.departmentName) · Hạn \(item.deadline)"
        if item.note.isEmpty {
            reasonLabel.isHidden = true
        } else {
            reasonLabel.text = "Nội dung: \(item.note)"
            reasonLabel.textColor = .secondaryLabel
            reasonLabel.isHidden = false
        }
        actionButton.configuration = .borderedProminent()
        setButton("Đánh giá", busy: busy, action: review)
        accessibilityLabel = "Chờ xác nhận. \(item.userName). \(item.content). \(metaLabel.text ?? "")"
    }

    private func setChat(_ action: (() -> Void)?) {
        onChat = action
        chatButton.isHidden = action == nil
    }

    private func setButton(_ title: String, busy: Bool, action: @escaping () -> Void) {
        actionButton.isHidden = false
        actionButton.setTitle(title, for: .normal)
        actionButton.isEnabled = !busy
        actionButton.addAction(UIAction { _ in action() }, for: .touchUpInside)
        busy ? spinner.startAnimating() : spinner.stopAnimating()
    }
}

enum WorkPresentation {
    static func status(_ status: String) -> String {
        switch status {
        case "pending_task", "pending": return "Chờ làm"
        case "overdue": return "Quá hạn"
        case "pending_completion": return "Chờ xác nhận"
        case "completed": return "Hoàn thành"
        case "rejected", "rejected_completion": return "Bị từ chối"
        default: return status
        }
    }

    static func statusColor(_ status: String) -> UIColor {
        switch status {
        case "completed": return .systemGreen
        case "overdue", "rejected", "rejected_completion": return .systemRed
        case "pending_completion": return .systemOrange
        default: return .systemIndigo
        }
    }
}

private final class WorkTaskDetailViewController: UIViewController, QLPreviewControllerDataSource {
    private let task: WorkTaskItem
    private let busy: Bool
    private let downloadDocument: (WorkApprovalItem) async throws -> URL
    private let onComplete: () -> Void
    private var previewURL: URL?
    private var openingFile = false
    private weak var openFileButton: UIButton?

    private let onOpenChat: (() -> Void)?

    init(
        task: WorkTaskItem,
        busy: Bool,
        downloadDocument: @escaping (WorkApprovalItem) async throws -> URL,
        onOpenChat: (() -> Void)?,
        onComplete: @escaping () -> Void
    ) {
        self.task = task
        self.busy = busy
        self.downloadDocument = downloadDocument
        self.onOpenChat = onOpenChat
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        title = "Chi tiết nhiệm vụ"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let rows = [
            label(task.title, .title2, .label),
            label(WorkPresentation.status(task.status), .headline, WorkPresentation.statusColor(task.status)),
            label(task.documentContent, .body, .secondaryLabel),
            label("Đơn vị: \(task.departmentName)", .body, .secondaryLabel),
            label("Hạn: \(task.deadline)", .body, .secondaryLabel),
            label(task.qualityPercent.map { "Chất lượng: \($0)%" } ?? "", .body, .secondaryLabel),
            label(task.note.isEmpty ? "" : "Nội dung đã gửi người giao: \(task.note)", .body, .secondaryLabel),
            label(task.rejectionReason.isEmpty ? "" : "Lý do từ chối: \(task.rejectionReason)", .body, .systemRed),
        ].filter { $0.text?.isEmpty == false }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 14
        if WorkHelpers.hasAttachedFile(task) {
            let fileName = task.fileName.isEmpty ? "Công văn đính kèm" : task.fileName
            stack.addArrangedSubview(label("Tệp đính kèm: \(fileName)", .body, .secondaryLabel))
            let openButton = UIButton(type: .system)
            openButton.configuration = .tinted()
            openButton.configuration?.title = "Mở tệp đính kèm"
            openButton.addAction(UIAction { [weak self] _ in self?.openAttachedFile() }, for: .touchUpInside)
            openFileButton = openButton
            stack.addArrangedSubview(openButton)
        }
        if let onOpenChat {
            let chatButton = UIButton(type: .system)
            chatButton.configuration = .tinted()
            chatButton.configuration?.title = "Trao đổi"
            chatButton.configuration?.image = UIImage(systemName: "bubble.left")
            chatButton.addAction(UIAction { _ in onOpenChat() }, for: .touchUpInside)
            stack.addArrangedSubview(chatButton)
        }
        if WorkHelpers.needsCompletion(task.status) {
            let button = UIButton(type: .system)
            button.configuration = .filled()
            let defaultTitle = task.isAdmin ? "Hoàn thành và chấm %" : "Nộp bằng chứng hoàn thành"
            button.configuration?.title = busy ? "Đang xử lý…" : defaultTitle
            button.isEnabled = !busy
            button.addAction(UIAction { [weak self] _ in self?.onComplete() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        embed(stack)
    }

    private func openAttachedFile() {
        guard !openingFile else { return }
        openingFile = true
        openFileButton?.isEnabled = false
        openFileButton?.configuration?.title = "Đang mở…"
        Task { [weak self] in
            guard let self else { return }
            defer {
                openingFile = false
                openFileButton?.isEnabled = true
                openFileButton?.configuration?.title = "Mở tệp đính kèm"
            }
            do {
                previewURL = try await downloadDocument(WorkHelpers.attachedDocument(task))
                let preview = QLPreviewController()
                preview.dataSource = self
                present(preview, animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                let alert = UIAlertController(
                    title: "Không thể mở tệp đính kèm",
                    message: (error as? LocalizedError)?.errorDescription ?? "Hãy thử lại hoặc đăng nhập lại.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Đóng", style: .default))
                present(alert, animated: true)
            }
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }

    private func label(_ text: String, _ style: UIFont.TextStyle, _ color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func embed(_ stack: UIStackView) {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
        ])
    }
}

private final class WorkDocumentViewController: UITableViewController, QLPreviewControllerDataSource {
    private let document: WorkApprovalItem
    private let isOps: Bool
    private let downloadDocument: (WorkApprovalItem) async throws -> URL
    private let groupedAssignments: [(String, [WorkDocumentAssignment])]
    private var previewURL: URL?
    private var openingFile = false

    private let onOpenChat: () -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void

    init(
        document: WorkApprovalItem,
        isOps: Bool,
        downloadDocument: @escaping (WorkApprovalItem) async throws -> URL,
        onOpenChat: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.document = document
        self.isOps = isOps
        self.downloadDocument = downloadDocument
        self.onOpenChat = onOpenChat
        self.onEdit = onEdit
        self.onDelete = onDelete
        groupedAssignments = Dictionary(grouping: document.assignments, by: \.departmentName)
            .map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        super.init(style: .insetGrouped)
        title = "Chi tiết công văn"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DocumentCell")
        var items: [UIBarButtonItem] = []
        if WorkCreatePolicy.showsDelete(canDelete: document.canDelete, isOps: isOps) {
            items.append(UIBarButtonItem(title: "Xóa", style: .plain, target: self, action: #selector(deleteDocument)))
        }
        if WorkCreatePolicy.showsEdit(canEdit: document.canEdit, isOps: isOps) {
            items.append(UIBarButtonItem(title: "Sửa", style: .done, target: self, action: #selector(editDocument)))
        }
        navigationItem.rightBarButtonItems = items.isEmpty ? nil : items
        if WorkCreatePolicy.showsLocked(canEdit: document.canEdit, canDelete: document.canDelete, isOps: isOps) {
            let footer = UILabel()
            footer.text = WorkCreatePolicy.lockedMessage
            footer.font = .preferredFont(forTextStyle: .footnote)
            footer.textColor = .secondaryLabel
            footer.numberOfLines = 0
            footer.textAlignment = .center
            footer.frame.size.height = 44
            tableView.tableFooterView = footer
        }
    }

    @objc private func editDocument() { onEdit() }

    @objc private func deleteDocument() { onDelete() }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 + groupedAssignments.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : groupedAssignments[section - 1].1.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Công văn" : groupedAssignments[section - 1].0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DocumentCell", for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.accessibilityTraits.remove(.button)
        cell.accessibilityHint = nil
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        if indexPath.section == 0 && indexPath.row == 1 {
            content.text = "Trao đổi"
            content.image = UIImage(systemName: "bubble.left")
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityTraits.insert(.button)
            cell.accessibilityLabel = "Trao đổi công việc"
        } else if indexPath.section == 0 {
            content.text = WorkHelpers.listTitle(document)
            let body = WorkHelpers.listSubtitle(document) ?? ""
            content.secondaryText = [body, "Hạn: \(document.deadline)", "Phê duyệt: \(document.approvalCount)/\(document.approvalTotal)"].filter { !$0.isEmpty }.joined(separator: "\n")
            content.image = UIImage(systemName: document.fileName.isEmpty ? "doc.text" : "doc")
            if !document.fileName.isEmpty {
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
                cell.accessibilityTraits.insert(.button)
                cell.accessibilityHint = "Mở tệp công văn"
            }
        } else {
            let assignment = groupedAssignments[indexPath.section - 1].1[indexPath.row]
            content.text = assignment.content
            let members = assignment.members.map { "\($0.name): \($0.status)" }.joined(separator: "\n")
            content.secondaryText = ["Hạn: \(assignment.deadline)", members].filter { !$0.isEmpty }.joined(separator: "\n")
            content.image = UIImage(systemName: "person.2")
        }
        content.imageProperties.tintColor = .systemIndigo
        cell.contentConfiguration = content
        cell.accessibilityLabel = [content.text, content.secondaryText].compactMap { $0 }.joined(separator: ". ")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && indexPath.row == 1 {
            onOpenChat()
            return
        }
        guard indexPath.section == 0, indexPath.row == 0, !document.fileName.isEmpty, !openingFile else { return }
        openingFile = true
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        tableView.cellForRow(at: indexPath)?.accessoryView = spinner
        Task { [weak self] in
            guard let self else { return }
            defer {
                openingFile = false
                tableView.reloadRows(at: [indexPath], with: .none)
            }
            do {
                previewURL = try await downloadDocument(document)
                let preview = QLPreviewController()
                preview.dataSource = self
                present(preview, animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                let alert = UIAlertController(
                    title: "Không thể mở công văn",
                    message: (error as? LocalizedError)?.errorDescription ?? "Hãy thử lại hoặc đăng nhập lại.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Đóng", style: .default))
                present(alert, animated: true)
            }
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }
}

private final class WorkReviewViewController: UIViewController, UITextViewDelegate {
    private let review: WorkCompletionReviewItem
    private let onSubmit: (Bool, Int?, String?) -> Void
    private let decision = UISegmentedControl(items: ["Duyệt", "Từ chối"])
    private let qualityField = UITextField()
    private let reasonView = UITextView()
    private let fieldLabel = UILabel()

    init(review: WorkCompletionReviewItem, onSubmit: @escaping (Bool, Int?, String?) -> Void) {
        self.review = review
        self.onSubmit = onSubmit
        super.init(nibName: nil, bundle: nil)
        title = "Đánh giá"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Gửi", style: .prominent, target: self, action: #selector(submit))
        decision.selectedSegmentIndex = 0
        decision.selectedSegmentTintColor = .systemIndigo
        decision.addTarget(self, action: #selector(decisionChanged), for: .valueChanged)
        qualityField.borderStyle = .roundedRect
        qualityField.keyboardType = .numberPad
        qualityField.text = "100"
        qualityField.placeholder = "0–100"
        qualityField.font = .preferredFont(forTextStyle: .body)
        qualityField.adjustsFontForContentSizeCategory = true
        qualityField.accessibilityLabel = "Phần trăm chất lượng"
        reasonView.font = .preferredFont(forTextStyle: .body)
        reasonView.adjustsFontForContentSizeCategory = true
        reasonView.layer.borderWidth = 1
        reasonView.layer.borderColor = UIColor.separator.cgColor
        reasonView.layer.cornerRadius = 8
        reasonView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        reasonView.accessibilityLabel = "Lý do từ chối"
        fieldLabel.font = .preferredFont(forTextStyle: .headline)
        fieldLabel.adjustsFontForContentSizeCategory = true
        let summary = UILabel()
        summary.text = "\(review.userName)\n\(review.content)\n\(review.departmentName) · Hạn \(review.deadline)"
        if !review.note.isEmpty {
            summary.text = (summary.text ?? "") + "\nNội dung từ người nộp: \(review.note)"
        }
        summary.font = .preferredFont(forTextStyle: .body)
        summary.adjustsFontForContentSizeCategory = true
        summary.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [summary, decision, fieldLabel, qualityField, reasonView])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
        decisionChanged()
    }

    @objc private func decisionChanged() {
        let approve = decision.selectedSegmentIndex == 0
        fieldLabel.text = approve ? "Chất lượng %" : "Lý do từ chối"
        qualityField.isHidden = !approve
        reasonView.isHidden = approve
    }

    @objc private func submit() {
        if decision.selectedSegmentIndex == 0 {
            let value = Int(qualityField.text ?? "") ?? -1
            guard (0...100).contains(value) else {
                showError("Phần trăm chất lượng phải từ 0 đến 100.")
                return
            }
            onSubmit(true, value, nil)
        } else {
            let reason = reasonView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else {
                showError("Cần nhập lý do từ chối.")
                return
            }
            let alert = UIAlertController(title: "Từ chối hoàn thành?", message: "Lý do sẽ được gửi cho người thực hiện.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
            alert.addAction(UIAlertAction(title: "Từ chối", style: .destructive) { [weak self] _ in self?.onSubmit(false, nil, reason) })
            present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Thông tin chưa hợp lệ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

extension WorkViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let item = pendingUploadTask else {
            clearPendingUpload()
            return
        }
        let ext = url.pathExtension.lowercased()
        guard Self.allowedUploadExtensions.contains(ext) else {
            clearPendingUpload()
            presentValidation("Chỉ chấp nhận tệp PDF, DOCX, Excel, PNG hoặc JPG.")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxUploadFileSize else {
                clearPendingUpload()
                presentValidation("Dung lượng tệp tối đa là 20MB.")
                return
            }
            guard !data.isEmpty else {
                clearPendingUpload()
                presentValidation("Tệp rỗng, vui lòng chọn lại.")
                return
            }
            let fileName = url.lastPathComponent
            let mime = Self.mimeType(for: url)
            submitEvidence(item: item, fileData: data, fileName: fileName, mimeType: mime)
        } catch {
            clearPendingUpload()
            presentValidation("Không thể đọc tệp đã chọn. Vui lòng thử lại.")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        clearPendingUpload()
    }
}

extension WorkViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let item = pendingUploadTask
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard let result = results.first, let item else {
                self.clearPendingUpload()
                return
            }
            let itemProvider = result.itemProvider
            guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
                self.clearPendingUpload()
                self.presentValidation("Không thể tải ảnh đã chọn.")
                return
            }
            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self, let image = object as? UIImage else {
                    DispatchQueue.main.async {
                        self?.clearPendingUpload()
                        self?.presentValidation("Không thể đọc ảnh đã chọn.")
                    }
                    return
                }
                guard let data = image.jpegData(compressionQuality: 0.85) else {
                    DispatchQueue.main.async {
                        self.clearPendingUpload()
                        self.presentValidation("Không thể xử lý định dạng ảnh.")
                    }
                    return
                }
                guard data.count <= Self.maxUploadFileSize else {
                    DispatchQueue.main.async {
                        self.clearPendingUpload()
                        self.presentValidation("Dung lượng ảnh tối đa là 20MB.")
                    }
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let fileName = "bang_chung_\(formatter.string(from: Date())).jpg"
                DispatchQueue.main.async {
                    self.submitEvidence(item: item, fileData: data, fileName: fileName, mimeType: "image/jpeg")
                }
            }
        }
    }
}

extension WorkViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let item = pendingUploadTask
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage),
                  let item else {
                self.clearPendingUpload()
                return
            }
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                self.clearPendingUpload()
                self.presentValidation("Không thể xử lý định dạng ảnh.")
                return
            }
            guard data.count <= Self.maxUploadFileSize else {
                self.clearPendingUpload()
                self.presentValidation("Dung lượng ảnh tối đa là 20MB.")
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "chup_anh_\(formatter.string(from: Date())).jpg"
            self.submitEvidence(item: item, fileData: data, fileName: fileName, mimeType: "image/jpeg")
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        clearPendingUpload()
        picker.dismiss(animated: true)
    }
}

private final class WorkTabsHeaderView: UIView {
    private let titleLabel = UILabel()
    private let control = UISegmentedControl(items: WorkListTab.allCases.map(\.title))
    private var onChange: ((WorkListTab) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor(red: 20 / 255, green: 53 / 255, blue: 95 / 255, alpha: 1)
        control.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange?(WorkListTab(rawValue: self.control.selectedSegmentIndex) ?? .todo)
        }, for: .valueChanged)
        let tabFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let tabFontSelected = UIFont.systemFont(ofSize: 10, weight: .bold)
        control.setTitleTextAttributes([.font: tabFont], for: .normal)
        control.setTitleTextAttributes([.font: tabFontSelected], for: .selected)
        let stack = UIStackView(arrangedSubviews: [titleLabel, control])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, tab: WorkListTab, counts: [WorkListTab: Int], onChange: @escaping (WorkListTab) -> Void) {
        titleLabel.text = title
        control.selectedSegmentIndex = tab.rawValue
        self.onChange = onChange
        for (index, item) in WorkListTab.allCases.enumerated() {
            let count = counts[item] ?? 0
            let badge = count > 99 ? "99+" : "\(count)"
            let label = count > 0 ? "\(item.title) \(badge)" : item.title
            control.setTitle(label, forSegmentAt: index)
            control.setEnabled(true, forSegmentAt: index)
        }
    }
}
