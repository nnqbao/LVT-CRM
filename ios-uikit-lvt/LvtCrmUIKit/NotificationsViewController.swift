import UIKit

@MainActor
final class NotificationsViewController: UITableViewController {
    private enum SectionKind {
        case controls
        case feedback(String)
        case loading
        case error(String)
        case empty
        case notifications([NotificationItem])
    }

    private let viewModel: NotificationsViewModel
    private let onOpenDestination: (NotificationDestination) -> Void
    private var pushObserver: NSObjectProtocol?
    private let unreadSwitch = UISwitch()
    private lazy var markAllItem = UIBarButtonItem(
        title: "Đọc tất cả",
        style: .plain,
        target: self,
        action: #selector(markAllRead)
    )

    init(
        viewModel: NotificationsViewModel,
        onOpenDestination: @escaping (NotificationDestination) -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenDestination = onOpenDestination
        super.init(style: .insetGrouped)
        title = "Thông báo"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let pushObserver {
            NotificationCenter.default.removeObserver(pushObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.estimatedRowHeight = 92
        tableView.rowHeight = UITableView.automaticDimension

        unreadSwitch.accessibilityLabel = "Chỉ hiện thông báo chưa đọc"
        unreadSwitch.addTarget(self, action: #selector(unreadOnlyChanged), for: .valueChanged)
        navigationItem.rightBarButtonItem = markAllItem

        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại thông báo"
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)

        let previousOnChange = viewModel.onChange
        viewModel.onChange = { [weak self] in
            previousOnChange?()
            self?.render()
        }
        pushObserver = NotificationCenter.default.addObserver(
            forName: .pushReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.viewModel.refresh() }
        }
        render()
        viewModel.refresh(initial: viewModel.items.isEmpty)
    }

    func refreshAfterDestination() {
        loadViewIfNeeded()
        viewModel.refresh()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sectionKinds.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKinds[section] {
        case .notifications(let items): return items.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionKinds[section] {
        case .notifications: return "Danh sách"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard case .controls = sectionKinds[section] else { return nil }
        let hours = viewModel.settings.milestonesHours
        guard !hours.isEmpty else { return "Nhắc hạn công tác và công việc" }
        return hours.map { $0 == 0 ? "Đến hạn" : "Trước \($0) giờ" }.joined(separator: " · ")
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        reset(cell)
        switch sectionKinds[indexPath.section] {
        case .controls:
            configureControls(cell)
        case .feedback(let message):
            configureFeedback(cell, message: message)
        case .loading:
            configureLoading(cell)
        case .error(let message):
            configureError(cell, message: message)
        case .empty:
            configureEmpty(cell)
        case .notifications(let items):
            configureNotification(cell, item: items[indexPath.row])
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKinds[indexPath.section] {
        case .error:
            viewModel.refresh(initial: true)
        case .notifications(let items):
            let item = items[indexPath.row]
            viewModel.open(item) { [weak self] opened in
                self?.onOpenDestination(NotificationDestination(
                    kind: opened.kind,
                    sourceType: opened.sourceType,
                    sourceId: opened.sourceId,
                    notificationKey: opened.key
                ))
            }
        default:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard case .notifications(let items) = sectionKinds[indexPath.section], viewModel.canDelete else {
            return nil
        }
        let item = items[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Xóa") { [weak self] _, _, complete in
            self?.viewModel.dismiss(item)
            complete(true)
        }
        action.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private var sectionKinds: [SectionKind] {
        var sections: [SectionKind] = [.controls]
        if let actionError = viewModel.actionError {
            sections.append(.feedback(actionError))
        }
        if let error = viewModel.error {
            sections.append(.error(error))
        } else if viewModel.loading {
            sections.append(.loading)
        } else if viewModel.visibleItems.isEmpty {
            sections.append(.empty)
        } else {
            sections.append(.notifications(viewModel.visibleItems))
        }
        return sections
    }

    private func reset(_ cell: UITableViewCell) {
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.isUserInteractionEnabled = true
        cell.accessibilityLabel = nil
        cell.accessibilityHint = nil
        cell.accessibilityTraits = []
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
    }

    private func configureControls(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        content.text = "Chỉ hiện chưa đọc"
        content.image = UIImage(systemName: "line.3.horizontal.decrease.circle")
        content.imageProperties.tintColor = .systemIndigo
        cell.contentConfiguration = content
        unreadSwitch.isOn = viewModel.unreadOnly
        unreadSwitch.isEnabled = viewModel.busyKey == nil
        cell.accessoryView = unreadSwitch
        cell.accessibilityLabel = "Chỉ hiện thông báo chưa đọc"
        cell.accessibilityValue = unreadSwitch.isOn ? "Bật" : "Tắt"
    }

    private func configureFeedback(_ cell: UITableViewCell, message: String) {
        var content = cell.defaultContentConfiguration()
        content.text = message
        content.textProperties.color = .systemRed
        content.image = UIImage(systemName: "exclamationmark.circle.fill")
        content.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = content
        cell.accessibilityLabel = "Lỗi thao tác. \(message)"
        cell.accessibilityTraits = .staticText
    }

    private func configureLoading(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        content.text = "Đang tải thông báo…"
        content.textProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        indicator.accessibilityLabel = "Đang tải"
        cell.accessoryView = indicator
        cell.accessibilityLabel = "Đang tải thông báo"
    }

    private func configureError(_ cell: UITableViewCell, message: String) {
        var content = cell.defaultContentConfiguration()
        content.text = "Không thể tải thông báo"
        content.secondaryText = message
        content.image = UIImage(systemName: "exclamationmark.triangle.fill")
        content.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.accessibilityLabel = "Không thể tải thông báo. \(message). Thử lại"
        cell.accessibilityHint = "Tải lại danh sách thông báo"
        cell.accessibilityTraits = .button
    }

    private func configureEmpty(_ cell: UITableViewCell) {
        let title = viewModel.unreadOnly ? "Không có thông báo chưa đọc" : "Chưa có thông báo"
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.secondaryText = "Khi có công tác hoặc công việc sắp đến hạn, thông báo sẽ hiện tại đây."
        content.image = UIImage(systemName: viewModel.unreadOnly ? "checkmark.circle" : "bell.slash")
        content.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessibilityLabel = "\(title). \(content.secondaryText ?? "")"
        cell.accessibilityTraits = .staticText
    }

    private func configureNotification(_ cell: UITableViewCell, item: NotificationItem) {
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = notificationDetails(item)
        content.textProperties.font = .preferredFont(forTextStyle: item.read ? .body : .headline)
        content.image = UIImage(systemName: item.read ? "bell" : "bell.badge.fill")
        content.imageProperties.tintColor = item.read ? .secondaryLabel : .systemRed
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = viewModel.busyKey == nil

        let state = item.read ? "Đã đọc" : "Chưa đọc"
        cell.accessibilityLabel = [state, kindLabel(item), item.title, item.description, dueText(item)]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        cell.accessibilityHint = item.sourceType == "duty_chat" || item.sourceType == "work_chat" || item.sourceType == "group_chat"
            ? "Mở trao đổi"
            : item.sourceType == PersonalTodos.notificationSourceType || item.kind == PersonalTodos.notificationKind
            ? "Mở Việc của tôi"
            : WorkApprovalRules.isDocumentNotification(sourceType: item.sourceType) && item.kind != "duty"
            ? "Mở công việc"
            : "Mở \(item.kind == "duty" ? "tab Lịch CT" : "tab Công việc")"
        cell.accessibilityTraits = .button
    }

    private func notificationDetails(_ item: NotificationItem) -> String {
        [kindLabel(item), item.description, dueText(item)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func kindLabel(_ item: NotificationItem) -> String {
        if item.sourceType == "duty_chat" || item.sourceType == "work_chat" || item.sourceType == "group_chat" { return "Trao đổi" }
        if item.sourceType == PersonalTodos.notificationSourceType || item.kind == PersonalTodos.notificationKind { return "Nhắc việc" }
        if item.sourceType == "completion_rejected" { return "Từ chối hoàn thành" }
        if item.kind == "duty" { return "Công tác" }
        if let label = WorkApprovalRules.notificationLabel(sourceType: item.sourceType) { return label }
        return "Công việc"
    }

    private func dueText(_ item: NotificationItem) -> String {
        guard item.dueAt > 0 else { return "" }
        let when = Self.dueFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.dueAt) / 1000))
        if item.sourceType == "duty_chat" || item.sourceType == "work_chat" || item.sourceType == "group_chat"
            || DutyWeekPresentation.isWeekNotification(item.sourceType) { return "Lúc \(when)" }
        return when
    }

    private func render() {
        unreadSwitch.isOn = viewModel.unreadOnly
        markAllItem.isEnabled = viewModel.unreadCount > 0 && viewModel.busyKey == nil
        markAllItem.accessibilityLabel = "Đánh dấu tất cả thông báo là đã đọc"
        if !viewModel.refreshing { refreshControl?.endRefreshing() }
        tableView.reloadData()
    }

    @objc private func unreadOnlyChanged() {
        viewModel.unreadOnly = unreadSwitch.isOn
    }

    @objc private func markAllRead() {
        viewModel.markAllRead()
    }

    @objc private func refresh() {
        viewModel.refresh()
    }

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()
}
