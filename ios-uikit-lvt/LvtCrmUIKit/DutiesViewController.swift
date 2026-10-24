import UIKit

@MainActor
final class DutiesViewController: UITableViewController {
    private enum SectionKind {
        case feedback(String)
        case loading
        case error(String)
        case mine([DutyItem])
        case created([DutyItem])
    }

    private let viewModel: DutiesViewModel
    private let chatRepository: ChatRepository
    var trailingAccessoryBarButtonItems: [UIBarButtonItem] = []
    private let searchHeader = ListSearchHeaderView()
    private var pendingFocusId: String?
    private var pendingOpenChat = false
    private weak var detailViewController: DutyDetailViewController?

    init(viewModel: DutiesViewModel, chatRepository: ChatRepository) {
        self.viewModel = viewModel
        self.chatRepository = chatRepository
        super.init(style: .insetGrouped)
        title = "Lịch công tác cá nhân"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(DutyTableViewCell.self, forCellReuseIdentifier: DutyTableViewCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StateCell")
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension

        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại danh sách công tác"
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.keyboardDismissMode = .onDrag
        searchHeader.onChange = { [weak self] values in self?.viewModel.search = values }
        searchHeader.onNeedsLayout = { [weak self] in self?.sizeSearchHeader() }
        searchHeader.configure(
            values: viewModel.search,
            queryPlaceholder: "Tìm theo tên hoặc nội dung công tác",
            personPlaceholder: "Tên người tham gia",
            includeLocation: true
        )
        tableView.tableHeaderView = searchHeader

        viewModel.onChange = { [weak self] in self?.render() }
        render()
        viewModel.refresh(initial: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sectionKinds.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKinds[section] {
        case .mine(let duties), .created(let duties): return max(duties.count, 1)
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        nil
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch sectionKinds[section] {
        case .mine:
            return sectionHeader(
                title: "Công tác của tôi",
                tab: viewModel.mineTab,
                onChange: { [weak self] tab in self?.viewModel.mineTab = tab }
            )
        case .created:
            return sectionHeader(
                title: "Công tác tôi tạo",
                tab: viewModel.createdTab,
                onChange: { [weak self] tab in self?.viewModel.createdTab = tab }
            )
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch sectionKinds[section] {
        case .mine, .created: return 96
        default: return UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if case .mine = sectionKinds[section], viewModel.showCreatedSection { return 36 }
        return 8
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sectionKinds[indexPath.section] {
        case .mine(let duties), .created(let duties):
            let created = {
                if case .created = sectionKinds[indexPath.section] { return true }
                return false
            }()
            guard !duties.isEmpty else {
                return emptyListCell(
                    at: indexPath,
                    created: created,
                    tab: created ? viewModel.createdTab : viewModel.mineTab,
                    filtered: created ? viewModel.createdSearchEmpty : viewModel.mineSearchEmpty
                )
            }
            let duty = duties[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DutyTableViewCell.reuseIdentifier,
                for: indexPath
            ) as! DutyTableViewCell
            cell.configure(
                duty: duty,
                showAttendanceStatus: viewModel.attendanceConfirmationEnabled,
                canMark: viewModel.canMark(duty),
                busy: viewModel.busyDutyId == duty.id,
                focused: duty.id == pendingFocusId,
                onChat: { [weak self] in
                    self?.presentChat(dutyId: duty.id, title: DutyListRules.displayTitle(duty))
                }
            )
            var actions = attendanceAccessibilityActions(for: duty) ?? []
            actions.append(UIAccessibilityCustomAction(name: "Trao đổi") { [weak self] _ in
                self?.presentChat(dutyId: duty.id, title: DutyListRules.displayTitle(duty))
                return true
            })
            cell.accessibilityCustomActions = actions
            return cell
        case .feedback(let message):
            return stateCell(
                at: indexPath,
                title: "Không thể cập nhật công tác",
                detail: message,
                image: "exclamationmark.circle.fill",
                color: .systemRed
            )
        case .loading:
            let cell = stateCell(
                at: indexPath,
                title: "Đang tải công tác…",
                detail: nil,
                image: nil,
                color: .secondaryLabel
            )
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            indicator.accessibilityLabel = "Đang tải"
            cell.accessoryView = indicator
            cell.accessibilityLabel = "Đang tải danh sách công tác"
            return cell
        case .error(let message):
            let cell = stateCell(
                at: indexPath,
                title: "Không thể tải công tác",
                detail: message,
                image: "exclamationmark.triangle.fill",
                color: .systemRed
            )
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityLabel = "Không thể tải công tác. \(message). Thử lại"
            cell.accessibilityHint = "Tải lại danh sách công tác"
            cell.accessibilityTraits = .button
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKinds[indexPath.section] {
        case .error:
            viewModel.refresh(initial: true)
        case .mine(let duties), .created(let duties):
            guard !duties.isEmpty else { return }
            showDetail(for: duties[indexPath.row])
        default:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch sectionKinds[indexPath.section] {
        case .mine(let duties) where !duties.isEmpty:
            return swipeActions(for: duties[indexPath.row])
        case .created(let duties) where !duties.isEmpty:
            return swipeActions(for: duties[indexPath.row])
        default:
            return nil
        }
    }

    private func swipeActions(for duty: DutyItem) -> UISwipeActionsConfiguration? {
        guard viewModel.canMark(duty), viewModel.busyDutyId == nil else { return nil }
        let absent = UIContextualAction(style: .destructive, title: "Vắng") { [weak self] _, _, done in
            self?.viewModel.setAttendance(dutyId: duty.id, status: "absent")
            done(true)
        }
        absent.image = UIImage(systemName: "xmark.circle")
        let attended = UIContextualAction(style: .normal, title: "Có mặt") { [weak self] _, _, done in
            self?.viewModel.setAttendance(dutyId: duty.id, status: "attended")
            done(true)
        }
        attended.backgroundColor = .systemTeal
        attended.image = UIImage(systemName: "checkmark.circle")
        let configuration = UISwipeActionsConfiguration(actions: [absent, attended])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func focus(dutyId: String, openChat: Bool = false) {
        loadViewIfNeeded()
        pendingFocusId = dutyId
        pendingOpenChat = openChat
        if let duty = viewModel.duty(id: dutyId) {
            let tab = DutyListRules.tab(for: duty)
            if viewModel.lists.mine.contains(where: { $0.id == duty.id }) { viewModel.mineTab = tab }
            if viewModel.lists.created.contains(where: { $0.id == duty.id }) { viewModel.createdTab = tab }
        }
        render()
    }

    func applyListTab(_ tab: DutyListTab) {
        loadViewIfNeeded()
        viewModel.mineTab = tab
        viewModel.createdTab = tab
        render()
    }

    private var sectionKinds: [SectionKind] {
        var sections: [SectionKind] = []
        if let actionError = viewModel.actionError {
            sections.append(.feedback(actionError))
        }
        if let error = viewModel.error {
            sections.append(.error(error))
        } else if viewModel.loading {
            sections.append(.loading)
        } else {
            sections.append(.mine(viewModel.visibleMine))
            if viewModel.showCreatedSection {
                sections.append(.created(viewModel.visibleCreated))
            }
        }
        return sections
    }

    private func render() {
        navigationItem.rightBarButtonItems = trailingAccessoryBarButtonItems.isEmpty
            ? nil
            : trailingAccessoryBarButtonItems
        if !viewModel.refreshing { refreshControl?.endRefreshing() }
        searchHeader.configure(
            values: viewModel.search,
            queryPlaceholder: "Tìm theo tên hoặc nội dung công tác",
            personPlaceholder: "Tên người tham gia",
            includeLocation: true
        )
        sizeSearchHeader()
        tableView.reloadData()
        updateVisibleDetail()
        processPendingFocusIfPossible()
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
        guard let dutyId = pendingFocusId, !viewModel.loading else { return }
        let openChat = pendingOpenChat
        if viewModel.error != nil {
            pendingFocusId = nil
            pendingOpenChat = false
            if openChat { presentChat(dutyId: dutyId, title: "Công tác") }
            return
        }
        pendingFocusId = nil
        pendingOpenChat = false
        guard let duty = viewModel.duty(id: dutyId) else {
            if openChat {
                presentChat(dutyId: dutyId, title: "Công tác")
            } else {
                presentMissingDutyAlert()
            }
            return
        }
        let tab = DutyListRules.tab(for: duty)
        if DutyListRules.isAssigned(duty) { viewModel.mineTab = tab }
        if !DutyListRules.isAssigned(duty) { viewModel.createdTab = tab }
        guard let section = sectionKinds.firstIndex(where: {
            switch $0 {
            case .mine(let duties), .created(let duties):
                return duties.contains(where: { $0.id == dutyId })
            default:
                return false
            }
        }) else {
            if openChat {
                presentChat(dutyId: duty.id, title: DutyListRules.displayTitle(duty))
            } else {
                presentMissingDutyAlert()
            }
            return
        }
        let row: Int
        switch sectionKinds[section] {
        case .mine(let duties), .created(let duties):
            guard let index = duties.firstIndex(where: { $0.id == dutyId }) else {
                presentMissingDutyAlert()
                return
            }
            row = index
        default:
            presentMissingDutyAlert()
            return
        }
        let indexPath = IndexPath(row: row, section: section)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.scrollToRow(at: indexPath, at: .middle, animated: !UIAccessibility.isReduceMotionEnabled)
            self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            UIAccessibility.post(notification: .screenChanged, argument: self.tableView.cellForRow(at: indexPath))
            self.showDetail(for: duty)
            if openChat {
                self.presentChat(dutyId: duty.id, title: DutyListRules.displayTitle(duty))
            }
        }
    }

    private func presentChat(dutyId: String, title: String) {
        let controller = ChatViewController(
            repository: chatRepository,
            target: ChatTarget(kind: .duty, entityId: dutyId, title: title)
        )
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func showDetail(for duty: DutyItem) {
        let detail = DutyDetailViewController(
            duty: duty,
            attendanceEnabled: viewModel.attendanceConfirmationEnabled,
            busy: viewModel.busyDutyId == duty.id,
            actionError: viewModel.actionError,
            onSetAttendance: { [weak self] status in
                self?.viewModel.setAttendance(dutyId: duty.id, status: status)
            },
            onOpenChat: { [weak self] in
                self?.presentChat(dutyId: duty.id, title: DutyListRules.displayTitle(duty))
            }
        )
        detailViewController = detail
        navigationController?.pushViewController(detail, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func updateVisibleDetail() {
        guard let detail = detailViewController, let duty = viewModel.duty(id: detail.dutyId) else { return }
        detail.update(
            duty: duty,
            attendanceEnabled: viewModel.attendanceConfirmationEnabled,
            busy: viewModel.busyDutyId == duty.id,
            actionError: viewModel.actionError
        )
    }

    private func presentMissingDutyAlert() {
        let alert = UIAlertController(
            title: "Không tìm thấy công tác",
            message: "Công tác này không còn tồn tại hoặc bạn không có quyền xem.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func attendanceAccessibilityActions(for duty: DutyItem) -> [UIAccessibilityCustomAction]? {
        guard viewModel.canMark(duty), viewModel.busyDutyId == nil else { return nil }
        return [
            UIAccessibilityCustomAction(name: "Đánh dấu có mặt") { [weak self] _ in
                self?.viewModel.setAttendance(dutyId: duty.id, status: "attended")
                return true
            },
            UIAccessibilityCustomAction(name: "Đánh dấu vắng") { [weak self] _ in
                self?.viewModel.setAttendance(dutyId: duty.id, status: "absent")
                return true
            },
        ]
    }

    private func emptyListCell(at indexPath: IndexPath, created: Bool, tab: DutyListTab, filtered: Bool = false) -> UITableViewCell {
        let detail: String
        if filtered {
            detail = "Không tìm thấy công tác phù hợp."
        } else {
            switch tab {
            case .past:
                detail = created ? "Chưa có công tác bạn tạo đã diễn ra." : "Chưa có sự kiện đã diễn ra."
            case .ongoing:
                detail = created ? "Chưa có công tác bạn tạo đang diễn ra." : "Chưa có sự kiện đang diễn ra."
            case .upcoming:
                detail = created ? "Chưa có công tác bạn tạo sắp diễn ra." : "Chưa có sự kiện sắp diễn ra."
            }
        }
        let cell = stateCell(
            at: indexPath,
            title: created ? "Công tác tôi tạo" : "Công tác của tôi",
            detail: detail,
            image: "briefcase",
            color: .secondaryLabel
        )
        cell.accessibilityLabel = "\(created ? "Công tác tôi tạo" : "Công tác của tôi"). \(detail)"
        cell.accessibilityTraits = .staticText
        return cell
    }

    private func sectionHeader(title: String, tab: DutyListTab, onChange: @escaping (DutyListTab) -> Void) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor(red: 20 / 255, green: 53 / 255, blue: 95 / 255, alpha: 1)
        let control = IconTabBar(
            items: DutyListTab.allCases.map { IconTabBar.Item(title: $0.title, systemImage: $0.systemImage) },
            selectedIndex: tab.rawValue
        )
        control.accessibilityLabel = "Danh sách công tác"
        control.addAction(UIAction { [weak control] _ in
            onChange(DutyListTab(rawValue: control?.selectedIndex ?? 0) ?? .upcoming)
        }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [titleLabel, control])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }

    private func stateCell(
        at indexPath: IndexPath,
        title: String,
        detail: String?,
        image: String?,
        color: UIColor
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StateCell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.accessibilityHint = nil
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
        return cell
    }

    @objc private func refresh() {
        viewModel.refresh()
    }
}

private final class DutyTableViewCell: UITableViewCell {
    static let reuseIdentifier = "DutyCell"

    private let timingLabel = UILabel()
    private let statusLabel = UILabel()
    private let titleLabel = UILabel()
    private let scheduleLabel = UILabel()
    private let chatButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var onChat: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default

        [timingLabel, statusLabel].forEach {
            $0.font = .preferredFont(forTextStyle: .caption1)
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        scheduleLabel.font = .preferredFont(forTextStyle: .subheadline)
        scheduleLabel.adjustsFontForContentSizeCategory = true
        scheduleLabel.textColor = .secondaryLabel
        scheduleLabel.numberOfLines = 0

        let statusStack = UIStackView(arrangedSubviews: [timingLabel, statusLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .firstBaseline
        statusStack.distribution = .equalSpacing
        statusStack.spacing = 12

        chatButton.configuration = .plain()
        chatButton.configuration?.title = "Trao đổi"
        chatButton.configuration?.image = UIImage(systemName: "bubble.left")
        chatButton.configuration?.imagePadding = 6
        chatButton.contentHorizontalAlignment = .leading
        chatButton.accessibilityLabel = "Trao đổi công tác"
        chatButton.addAction(UIAction { [weak self] _ in self?.onChat?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [statusStack, titleLabel, scheduleLabel, chatButton])
        stack.axis = .vertical
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

    func configure(
        duty: DutyItem,
        showAttendanceStatus: Bool,
        canMark: Bool,
        busy: Bool,
        focused: Bool,
        onChat: @escaping () -> Void
    ) {
        titleLabel.text = DutyListRules.displayTitle(duty)
        scheduleLabel.text = DutyPresentation.schedule(duty)
        timingLabel.text = DutyPresentation.timing(duty)
        timingLabel.textColor = DutyPresentation.timingColor(duty)
        // When attendance confirmation is off, backend defaults myStatus to "attended".
        // Do not surface that synthetic label — LVT does not use attendance in Công tác.
        statusLabel.isHidden = !showAttendanceStatus
        if showAttendanceStatus {
            statusLabel.text = DutyPresentation.status(duty.myStatus)
            statusLabel.textColor = DutyPresentation.statusColor(duty.myStatus)
        } else {
            statusLabel.text = nil
        }
        self.onChat = onChat
        backgroundColor = focused ? UIColor.systemIndigo.withAlphaComponent(0.12) : .secondarySystemGroupedBackground
        accessoryView = busy ? activityIndicator : nil
        accessoryType = busy ? .none : .disclosureIndicator
        if busy { activityIndicator.startAnimating() } else { activityIndicator.stopAnimating() }
        isUserInteractionEnabled = !busy
        isAccessibilityElement = true
        accessibilityTraits = .button
        var accessibilityParts = [
            DutyPresentation.timing(duty),
            DutyListRules.displayTitle(duty),
            DutyPresentation.schedule(duty),
        ]
        if showAttendanceStatus {
            accessibilityParts.insert(DutyPresentation.status(duty.myStatus), at: 1)
        }
        accessibilityLabel = accessibilityParts.joined(separator: ". ")
        accessibilityHint = canMark
            ? "Mở chi tiết. Có các thao tác xác nhận tham dự."
            : "Mở chi tiết công tác."
    }
}

@MainActor
private final class DutyDetailViewController: UITableViewController {
    private enum Section {
        case error(String)
        case content
        case information([(String, String)])
        case attendance
        case chat
    }

    private(set) var dutyId: String
    private var duty: DutyItem
    private var attendanceEnabled: Bool
    private var busy: Bool
    private var actionError: String?
    private let onSetAttendance: (String) -> Void
    private let onOpenChat: () -> Void

    init(
        duty: DutyItem,
        attendanceEnabled: Bool,
        busy: Bool,
        actionError: String?,
        onSetAttendance: @escaping (String) -> Void,
        onOpenChat: @escaping () -> Void
    ) {
        dutyId = duty.id
        self.duty = duty
        self.attendanceEnabled = attendanceEnabled
        self.busy = busy
        self.actionError = actionError
        self.onSetAttendance = onSetAttendance
        self.onOpenChat = onOpenChat
        super.init(style: .insetGrouped)
        title = "Chi tiết công tác"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DetailCell")
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .information(let rows): return rows.count
        case .attendance: return 2
        case .chat: return 1
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .information: return "Thông tin"
        case .attendance: return "Xác nhận tham dự"
        case .chat: return nil
        default: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.isUserInteractionEnabled = true
        cell.accessibilityHint = nil
        cell.accessibilityTraits = .staticText
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        switch sections[indexPath.section] {
        case .error(let message):
            content.text = "Không thể cập nhật công tác"
            content.secondaryText = message
            content.image = UIImage(systemName: "exclamationmark.circle.fill")
            content.imageProperties.tintColor = .systemRed
            content.textProperties.color = .systemRed
            cell.accessibilityLabel = "Không thể cập nhật công tác. \(message)"
        case .content:
            content.text = duty.content
            content.textProperties.font = .preferredFont(forTextStyle: .title3)
            content.textProperties.color = .label
            cell.accessibilityLabel = duty.content
        case .information(let rows):
            let row = rows[indexPath.row]
            content.text = row.0
            content.secondaryText = row.1
            cell.accessibilityLabel = "\(row.0). \(row.1)"
        case .attendance:
            let attended = indexPath.row == 0
            content.text = attended ? "Có mặt" : "Vắng"
            content.image = UIImage(systemName: attended ? "checkmark.circle.fill" : "xmark.circle.fill")
            content.imageProperties.tintColor = attended ? .systemTeal : .systemRed
            cell.selectionStyle = busy ? .none : .default
            cell.isUserInteractionEnabled = !busy
            cell.accessibilityTraits = busy ? .notEnabled : .button
            cell.accessibilityLabel = attended ? "Xác nhận có mặt" : "Xác nhận vắng"
            if busy {
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.startAnimating()
                cell.accessoryView = indicator
            }
        case .chat:
            content.text = "Trao đổi"
            content.image = UIImage(systemName: "bubble.left")
            content.imageProperties.tintColor = .systemIndigo
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = "Trao đổi công tác"
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .attendance where !busy:
            onSetAttendance(indexPath.row == 0 ? "attended" : "absent")
        case .chat:
            onOpenChat()
        default:
            break
        }
    }

    func update(
        duty: DutyItem,
        attendanceEnabled: Bool,
        busy: Bool,
        actionError: String?
    ) {
        dutyId = duty.id
        self.duty = duty
        self.attendanceEnabled = attendanceEnabled
        self.busy = busy
        self.actionError = actionError
        tableView.reloadData()
        if !busy, actionError == nil, attendanceEnabled {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Trạng thái công tác: \(DutyPresentation.status(duty.myStatus))"
            )
        }
    }

    private var sections: [Section] {
        var result: [Section] = []
        if let actionError { result.append(.error(actionError)) }
        result.append(.content)
        result.append(.information(informationRows))
        if attendanceEnabled && duty.isMine && duty.canMarkAttendance {
            result.append(.attendance)
        }
        result.append(.chat)
        return result
    }

    private var informationRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Thời gian", DutyPresentation.schedule(duty)),
        ]
        if attendanceEnabled {
            rows.append(("Trạng thái", DutyPresentation.status(duty.myStatus)))
        }
        if !duty.locationNames.isEmpty {
            rows.append(("Địa điểm", duty.locationNames.joined(separator: ", ")))
        }
        if !duty.departmentNames.isEmpty {
            rows.append(("Tổ/phòng", duty.departmentNames.joined(separator: ", ")))
        }
        rows.append(contentsOf: duty.departmentParticipants.compactMap { participants in
            guard !participants.participantNames.isEmpty else { return nil }
            return (participants.departmentName, participants.participantNames.joined(separator: ", "))
        })
        if !duty.participantNames.isEmpty {
            rows.append(("Thành phần", duty.participantNames.joined(separator: ", ")))
        }
        let other = duty.otherParticipants.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty {
            rows.append(("Thành phần khác", other))
        }
        return rows
    }
}

private enum DutyPresentation {
    static func schedule(_ duty: DutyItem) -> String {
        let dates = duty.startDate == duty.endDate
            ? duty.startDate
            : "\(duty.startDate) → \(duty.endDate)"
        return duty.allDay ? "\(dates) · Cả ngày" : "\(dates) · \(duty.startTime)–\(duty.endTime)"
    }

    static func timing(_ duty: DutyItem) -> String {
        if duty.isOngoing { return "Đang diễn ra" }
        if duty.isOverdue { return "Đã kết thúc" }
        if duty.isUpcoming { return "Sắp tới" }
        return "Theo lịch"
    }

    static func timingColor(_ duty: DutyItem) -> UIColor {
        if duty.isOngoing { return .systemGreen }
        if duty.isUpcoming { return .systemIndigo }
        return .secondaryLabel
    }

    static func status(_ status: String) -> String {
        switch status {
        case "attended": return "Có mặt"
        case "absent": return "Vắng"
        default: return "Chưa xác nhận"
        }
    }

    static func statusColor(_ status: String) -> UIColor {
        switch status {
        case "attended": return .systemGreen
        case "absent": return .systemRed
        default: return .systemOrange
        }
    }
}
