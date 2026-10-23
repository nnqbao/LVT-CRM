import UIKit

/// Báo cáo › Bán trú (web `BoardingPage` / `BoardingReportsView` / `BoardingManagement`).
/// Everyone whose Bán trú menu is not hidden reads "Danh sách tham gia" (own department, or the whole school
/// with `view_all`); admin/mod also get "Kỳ bán trú" management. The server enforces both.
@MainActor
final class BoardingViewController: UITableViewController {
    enum Pane: Int { case participants, periods }

    private enum Row {
        case message(title: String, detail: String?, image: String, color: UIColor)
        case loading(String)
        case periodPicker
        case stats
        case participant(BoardingPerson)
        case adminPeriod(BoardingAdminPeriod)
    }

    private struct Section {
        let title: String?
        let rows: [Row]
    }

    private let repository: BoardingRepository
    private let canManage: Bool
    private let control = UISegmentedControl(items: ["Danh sách tham gia", "Kỳ bán trú"])
    private var pane: Pane = .participants
    private var report: BoardingReport?
    private var reportError: String?
    private var selectedPeriodId: String?
    private var admin: BoardingAdminData?
    private var adminError: String?
    private var feedback: (text: String, isError: Bool)?
    private var busy = false
    private var loadTask: Task<Void, Never>?

    init(repository: BoardingRepository, canManage: Bool) {
        self.repository = repository
        self.canManage = canManage
        super.init(style: .insetGrouped)
        title = "Bán trú"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BoardingCell")
        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại Bán trú"
        refreshControl?.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        installHelpButton(.boarding)
        if canManage {
            control.selectedSegmentIndex = pane.rawValue
            control.accessibilityLabel = "Chọn mục Bán trú"
            control.addAction(UIAction { [weak self] _ in
                guard let self, let next = Pane(rawValue: control.selectedSegmentIndex) else { return }
                pane = next
                feedback = nil
                render()
                if (next == .periods && admin == nil) || (next == .participants && report == nil) { reload() }
            }, for: .valueChanged)
            let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
            control.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
                control.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
                control.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                control.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            ])
            tableView.tableHeaderView = header
        }
        render()
        reload()
    }

    // MARK: Loading

    private func reload() {
        loadTask?.cancel()
        let currentPane = pane
        let periodId = selectedPeriodId
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshControl?.endRefreshing() }
            switch currentPane {
            case .participants:
                do {
                    let loaded = try await repository.report(periodId: periodId)
                    guard !Task.isCancelled else { return }
                    report = loaded
                    reportError = nil
                    selectedPeriodId = loaded.selectedPeriod?.id
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    reportError = Boarding.errorMessage(error, fallback: "Không thể tải danh sách bán trú. Vui lòng thử lại.")
                    // A period that disappeared or became forbidden falls back to the server default.
                    if (error as? ConvexException)?.code == "BOARDING_PERIOD_FORBIDDEN" {
                        selectedPeriodId = nil
                    }
                }
            case .periods:
                do {
                    let loaded = try await repository.listAdmin()
                    guard !Task.isCancelled else { return }
                    admin = loaded
                    adminError = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    adminError = Boarding.errorMessage(error, fallback: "Không thể tải dữ liệu bán trú. Vui lòng thử lại.")
                }
            }
            render()
        }
    }

    private func render() {
        if canManage && pane == .periods {
            let add = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.openEditor(nil) })
            add.accessibilityLabel = "Thêm kỳ bán trú"
            add.isEnabled = admin != nil && !busy
            navigationItem.rightBarButtonItem = add
        } else {
            navigationItem.rightBarButtonItem = nil
        }
        sections = buildSections()
        tableView.reloadData()
    }

    private var sections: [Section] = []

    private func buildSections() -> [Section] {
        var result: [Section] = []
        if let feedback {
            result.append(Section(title: nil, rows: [.message(
                title: feedback.text,
                detail: nil,
                image: feedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                color: feedback.isError ? .systemRed : .systemGreen
            )]))
        }
        switch pane {
        case .participants: result += participantSections()
        case .periods: result += periodSections()
        }
        return result
    }

    private func participantSections() -> [Section] {
        guard let report else {
            if let reportError {
                return [Section(title: nil, rows: [.message(title: "Không thể tải Bán trú", detail: reportError, image: "exclamationmark.triangle.fill", color: .systemRed)])]
            }
            return [Section(title: nil, rows: [.loading("Đang tải các kỳ bán trú…")])]
        }
        var result: [Section] = [Section(title: "Chọn kỳ cần xem", rows: [.periodPicker])]
        if let reportError {
            result.append(Section(title: nil, rows: [.message(title: reportError, detail: nil, image: "exclamationmark.circle.fill", color: .systemRed)]))
        }
        guard report.selectedPeriod != nil else {
            result.append(Section(title: nil, rows: [.message(
                title: "Chưa có kỳ bán trú để xem",
                detail: "Quản trị viên cần tạo kỳ bán trú và thêm giáo viên tham gia trước.",
                image: "sun.max",
                color: .secondaryLabel
            )]))
            return result
        }
        result.append(Section(title: nil, rows: [.stats]))
        if report.groups.isEmpty {
            result.append(Section(title: nil, rows: [.message(
                title: "Chưa có giáo viên tham gia trong kỳ này",
                detail: "Hãy chọn kỳ khác. Quản trị viên cập nhật danh sách ở menu Bán trú › Kỳ bán trú.",
                image: "sun.max",
                color: .secondaryLabel
            )]))
        }
        for group in report.groups {
            result.append(Section(
                title: "\(group.departmentName) · \(group.participants.count) giáo viên",
                rows: group.participants.map { .participant($0) }
            ))
        }
        return result
    }

    private func periodSections() -> [Section] {
        guard let admin else {
            if let adminError {
                return [Section(title: nil, rows: [.message(title: "Không thể tải Kỳ bán trú", detail: adminError, image: "exclamationmark.triangle.fill", color: .systemRed)])]
            }
            return [Section(title: nil, rows: [.loading("Đang tải dữ liệu bán trú…")])]
        }
        guard !admin.periods.isEmpty else {
            return [Section(title: "Các kỳ bán trú đã thiết lập (0)", rows: [.message(
                title: "Chưa có kỳ bán trú",
                detail: "Tạo kỳ đầu tiên để bắt đầu phân công giáo viên. Bấm ＋ để thêm.",
                image: "calendar.badge.plus",
                color: .secondaryLabel
            )])]
        }
        return [Section(
            title: "Các kỳ bán trú đã thiết lập (\(admin.periods.count))",
            rows: admin.periods.map { .adminPeriod($0) }
        )]
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BoardingCell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.accessibilityTraits = .staticText
        cell.accessibilityHint = nil
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        switch sections[indexPath.section].rows[indexPath.row] {
        case .message(let title, let detail, let image, let color):
            content.text = title
            content.secondaryText = detail
            content.textProperties.color = color
            content.image = UIImage(systemName: image)
            content.imageProperties.tintColor = color
        case .loading(let text):
            content.text = text
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        case .periodPicker:
            let report = report
            content.text = Boarding.periodLabel(report?.selectedPeriod)
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            var lines = [report.map(Boarding.scopeText) ?? ""]
            if let report, !report.periods.isEmpty {
                let year = Boarding.currentSchoolYear()
                if !Boarding.hasPeriod(forSchoolYear: year, in: report.periods) {
                    lines.append("Chưa có kỳ bán trú cho năm học \(year).")
                }
            }
            content.secondaryText = lines.filter { !$0.isEmpty }.joined(separator: "\n")
            content.image = UIImage(systemName: "calendar")
            content.imageProperties.tintColor = .systemIndigo
            if (report?.periods.count ?? 0) > 1 {
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                cell.accessibilityTraits = .button
                cell.accessibilityHint = "Chọn kỳ bán trú khác"
            }
        case .stats:
            let total = report?.totalParticipants ?? 0
            let groups = report?.groups.count ?? 0
            content.text = "\(total) giáo viên tham gia · \(groups) phòng ban"
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = "Danh sách do quản trị viên thiết lập trong menu Bán trú."
            content.image = UIImage(systemName: "person.3")
            content.imageProperties.tintColor = .systemIndigo
        case .participant(let person):
            content.text = person.name
            content.secondaryText = [person.positionName, person.email].filter { !$0.isEmpty }.joined(separator: " · ")
            let badge = UILabel()
            badge.text = "Đã đăng ký"
            badge.font = .preferredFont(forTextStyle: .caption1)
            badge.adjustsFontForContentSizeCategory = true
            badge.textColor = .systemGreen
            badge.sizeToFit()
            cell.accessoryView = badge
        case .adminPeriod(let period):
            content.text = Boarding.periodLabel(semester: period.semester, schoolYear: period.schoolYear)
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            let names = period.participants.map(\.name).joined(separator: ", ")
            content.secondaryText = ["\(period.participants.count) giáo viên tham gia", names].filter { !$0.isEmpty }.joined(separator: "\n")
            content.image = UIImage(systemName: "calendar")
            content.imageProperties.tintColor = .systemIndigo
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = busy ? .none : .default
            cell.accessibilityTraits = .button
            cell.accessibilityHint = "Sửa hoặc xóa kỳ bán trú"
        }
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = content
        var label = [content.text, content.secondaryText].compactMap { $0 }.joined(separator: ". ")
        if case .participant = sections[indexPath.section].rows[indexPath.row] { label += ". Đã đăng ký" }
        cell.accessibilityLabel = label
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .periodPicker:
            choosePeriod(from: tableView.cellForRow(at: indexPath))
        case .adminPeriod(let period):
            guard !busy else { return }
            periodActions(period, from: tableView.cellForRow(at: indexPath))
        default:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard case .adminPeriod(let period) = sections[indexPath.section].rows[indexPath.row], !busy else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Xóa") { [weak self] _, _, done in
            self?.confirmDelete(period)
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: "Sửa") { [weak self] _, _, done in
            self?.openEditor(period)
            done(true)
        }
        edit.backgroundColor = .systemIndigo
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    // MARK: Actions

    private func choosePeriod(from cell: UITableViewCell?) {
        guard let report, report.periods.count > 1 else { return }
        let sheet = UIAlertController(title: "Kỳ bán trú", message: nil, preferredStyle: .actionSheet)
        for period in report.periods {
            let title = Boarding.periodLabel(period) + (period.id == report.selectedPeriod?.id ? " ✓" : "")
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                selectedPeriodId = period.id
                reload()
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        anchor(sheet, to: cell)
        present(sheet, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func periodActions(_ period: BoardingAdminPeriod, from cell: UITableViewCell?) {
        let sheet = UIAlertController(
            title: Boarding.periodLabel(semester: period.semester, schoolYear: period.schoolYear),
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Sửa", style: .default) { [weak self] _ in self?.openEditor(period) })
        sheet.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in self?.confirmDelete(period) })
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        anchor(sheet, to: cell)
        present(sheet, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func anchor(_ sheet: UIAlertController, to cell: UITableViewCell?) {
        guard let popover = sheet.popoverPresentationController else { return }
        popover.sourceView = cell ?? view
        popover.sourceRect = (cell ?? view).bounds
    }

    private func openEditor(_ period: BoardingAdminPeriod?) {
        guard let admin else { return }
        let editor = BoardingPeriodEditorViewController(
            repository: repository,
            users: admin.users,
            period: period
        ) { [weak self] message in
            guard let self else { return }
            feedback = (message, false)
            report = nil
            reload()
        }
        navigationController?.pushViewController(editor, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func confirmDelete(_ period: BoardingAdminPeriod) {
        let alert = UIAlertController(title: Boarding.deletePrompt(period), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in self?.delete(period) })
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func delete(_ period: BoardingAdminPeriod) {
        guard !busy else { return }
        busy = true
        feedback = nil
        render()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.remove(id: period.id)
                feedback = ("Đã xóa kỳ bán trú.", false)
                report = nil
                if selectedPeriodId == period.id { selectedPeriodId = nil }
            } catch {
                feedback = (Boarding.errorMessage(error), true)
            }
            busy = false
            reload()
            if let feedback { UIAccessibility.post(notification: .announcement, argument: feedback.text) }
        }
    }
}

/// Add/edit one Kỳ bán trú (Học kỳ, Năm học, Giáo viên tham gia) with the web validation.
@MainActor
private final class BoardingPeriodEditorViewController: UITableViewController {
    private let repository: BoardingRepository
    private let users: [BoardingPerson]
    private let period: BoardingAdminPeriod?
    private let onSaved: (String) -> Void
    private var form: BoardingForm
    private let years: [String]
    private var saving = false

    init(repository: BoardingRepository, users: [BoardingPerson], period: BoardingAdminPeriod?, onSaved: @escaping (String) -> Void) {
        self.repository = repository
        self.users = users
        self.period = period
        self.onSaved = onSaved
        if let period {
            form = BoardingForm(semester: period.semester, schoolYear: period.schoolYear, participantUserIds: period.participantUserIds)
        } else {
            form = Boarding.emptyForm()
        }
        years = Boarding.schoolYearOptions(including: period?.schoolYear)
        super.init(style: .insetGrouped)
        title = period == nil ? "Thêm kỳ bán trú" : "Sửa kỳ bán trú"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EditorCell")
        tableView.rowHeight = UITableView.automaticDimension
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", primaryAction: UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        })
        updateSaveButton()
    }

    private func updateSaveButton() {
        let title = saving ? "Đang lưu…" : (period == nil ? "Tạo kỳ" : "Lưu")
        let item = UIBarButtonItem(title: title, primaryAction: UIAction { [weak self] _ in self?.save() })
        item.style = .prominent
        item.isEnabled = !saving
        item.accessibilityLabel = period == nil ? "Tạo kỳ bán trú" : "Lưu thay đổi"
        navigationItem.rightBarButtonItem = item
    }

    private var selectedPeople: [BoardingPerson] {
        form.participantUserIds.compactMap { id in users.first { $0.id == id } }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return years.count
        default: return 1 + selectedPeople.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Học kỳ", "Năm học", "Giáo viên tham gia (\(form.participantUserIds.count))"][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 && form.participantUserIds.isEmpty ? "Chưa có giáo viên tham gia. Bấm “Thêm giáo viên” để chọn từ danh sách." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EditorCell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.color = .secondaryLabel
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.accessibilityTraits = .button
        switch indexPath.section {
        case 0:
            let semester = indexPath.row + 1
            content.text = "Học kỳ \(semester)"
            content.secondaryText = semester == 1 ? "Nửa đầu năm học" : "Nửa sau năm học"
            let checked = form.semester == semester
            cell.accessoryType = checked ? .checkmark : .none
            if checked { cell.accessibilityTraits.insert(.selected) }
        case 1:
            let year = years[indexPath.row]
            content.text = year
            let checked = form.schoolYear == year
            cell.accessoryType = checked ? .checkmark : .none
            if checked { cell.accessibilityTraits.insert(.selected) }
        default:
            if indexPath.row == 0 {
                content.text = "＋ Thêm giáo viên"
                content.textProperties.color = .tintColor
            } else {
                let person = selectedPeople[indexPath.row - 1]
                content.text = person.name
                content.secondaryText = [person.positionName.isEmpty ? "Chưa gán chức vụ" : person.positionName, person.departmentName]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                cell.selectionStyle = .none
                cell.accessibilityTraits = .staticText
            }
        }
        cell.contentConfiguration = content
        cell.accessibilityHint = indexPath.section == 2 && indexPath.row > 0 ? "Vuốt để bỏ chọn" : nil
        cell.accessibilityLabel = indexPath.section == 2 && indexPath.row == 0
            ? "Thêm giáo viên tham gia"
            : [content.text, content.secondaryText].compactMap { $0 }.joined(separator: ". ")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !saving else { return }
        switch indexPath.section {
        case 0: form.semester = indexPath.row + 1
        case 1: form.schoolYear = years[indexPath.row]
        default:
            guard indexPath.row == 0 else { return }
            let picker = BoardingTeacherPickerViewController(users: users, selected: form.participantUserIds) { [weak self] ids in
                self?.form.participantUserIds = ids
                self?.tableView.reloadData()
            }
            navigationController?.pushViewController(picker, animated: !UIAccessibility.isReduceMotionEnabled)
            return
        }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2, indexPath.row > 0, !saving else { return nil }
        let person = selectedPeople[indexPath.row - 1]
        let remove = UIContextualAction(style: .destructive, title: "Bỏ chọn") { [weak self] _, _, done in
            self?.form.participantUserIds.removeAll { $0 == person.id }
            self?.tableView.reloadData()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    private func save() {
        guard !saving else { return }
        if let message = Boarding.validate(form) {
            showError(message)
            return
        }
        saving = true
        updateSaveButton()
        let editingId = period?.id
        let form = form
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.save(form, id: editingId)
                onSaved(editingId == nil ? "Đã thêm kỳ bán trú." : "Đã cập nhật kỳ bán trú.")
                navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                saving = false
                updateSaveButton()
                showError(Boarding.errorMessage(error))
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Không thể lưu kỳ bán trú", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

/// Teacher multi-select with search, "Chọn tất cả" / "Bỏ chọn" (web TeacherPicker).
@MainActor
private final class BoardingTeacherPickerViewController: UITableViewController, UISearchResultsUpdating {
    private let users: [BoardingPerson]
    private var selected: [String]
    private let onDone: ([String]) -> Void
    private var query = ""
    private let searchController = UISearchController(searchResultsController: nil)

    init(users: [BoardingPerson], selected: [String], onDone: @escaping ([String]) -> Void) {
        self.users = users
        self.selected = selected
        self.onDone = onDone
        super.init(style: .insetGrouped)
        title = "Chọn giáo viên tham gia"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TeacherCell")
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Tìm theo tên, email, phòng ban…"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        let done = UIBarButtonItem(title: "Hoàn thành", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            onDone(selected)
            navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        })
        done.style = .prominent
        navigationItem.rightBarButtonItem = done
        toolbarItems = [
            UIBarButtonItem(title: "Chọn tất cả", primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                selected = users.map(\.id)
                tableView.reloadData()
            }),
            .flexibleSpace(),
            UIBarButtonItem(title: "Bỏ chọn", primaryAction: UIAction { [weak self] _ in
                self?.selected = []
                self?.tableView.reloadData()
            }),
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    private var filtered: [BoardingPerson] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
        guard !needle.isEmpty else { return users }
        return users.filter { person in
            "\(person.name) \(person.email) \(person.departmentName) \(person.positionName)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
                .contains(needle)
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(filtered.count, 1) }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "\(selected.count) giáo viên đã chọn"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TeacherCell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.color = .secondaryLabel
        let list = filtered
        guard list.indices.contains(indexPath.row) else {
            content.text = "Không tìm thấy giáo viên phù hợp."
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.accessibilityTraits = .staticText
            return cell
        }
        let person = list[indexPath.row]
        let checked = selected.contains(person.id)
        content.text = person.name
        content.secondaryText = [
            [person.positionName.isEmpty ? "Chưa gán chức vụ" : person.positionName, person.departmentName].filter { !$0.isEmpty }.joined(separator: " · "),
            person.email,
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        cell.contentConfiguration = content
        cell.accessoryType = checked ? .checkmark : .none
        cell.selectionStyle = .default
        cell.accessibilityTraits = checked ? [.button, .selected] : [.button]
        cell.accessibilityLabel = [content.text, content.secondaryText].compactMap { $0 }.joined(separator: ". ")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let list = filtered
        guard list.indices.contains(indexPath.row) else { return }
        let id = list[indexPath.row].id
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        if let header = tableView.headerView(forSection: 0) {
            var config = header.defaultContentConfiguration()
            config.text = "\(selected.count) giáo viên đã chọn"
            header.contentConfiguration = config
        }
    }
}
