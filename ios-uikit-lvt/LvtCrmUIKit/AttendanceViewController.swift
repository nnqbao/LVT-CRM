import UIKit

/// Điểm danh (Giám thị / admin / mod): pick a grade → open a class → tick "Vắng" → Lưu lớp. Everyone attends by
/// default. Mirrors src/attendance/AttendancePage.jsx; Excel template/import stay on the web.
@MainActor
final class AttendanceViewController: UITableViewController {
    private enum Section {
        case status([StatusRow])
        case klass(AttendanceClass)
    }

    private enum StatusRow {
        case info(String, String?)
        case banner(String, String?, HomeroomTone, String)
    }

    private enum Item {
        case header(AttendanceClass)
        case student(AttendanceClass, AttendanceStudent, Int)
        case empty
        case saveBar(AttendanceClass)
    }

    private static let gradeKey = "lvt.attendance.gradeTab"

    private let repository: SupervisorAttendanceRepository
    private let session: UserSession
    private let subtitleLabel = UILabel()
    private let noteLabel = UILabel()
    private let gradeControl = UISegmentedControl(items: SupervisorAttendance.gradeTabs.map { "Lớp \($0)" })
    private lazy var dayNavigator = HomeroomDayNavigator(date: VietnamDate.today())
    private let todayButton = UIButton(type: .system)
    private let dateRow = UIStackView()

    /// nil until the first roster arrives: the server decides "today" (Giám thị may only read today).
    private var requestedDate: String?
    private var grade: Int
    private var roster: AttendanceRoster?
    private var loading = false
    private var loadError: String?
    private var openClassId: String?
    private var draft: AttendanceClassDraft?
    private var saving = false
    private var saveError: String?
    private var saveSuccess: String?
    private var sections: [Section] = []
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var generation = 0

    /// Unsaved ticks in the open class (used by the tab bar before switching away).
    var hasUnsavedChanges: Bool { draft?.isDirty == true }

    init(repository: SupervisorAttendanceRepository, session: UserSession) {
        self.repository = repository
        self.session = session
        let stored = UserDefaults.standard.integer(forKey: Self.gradeKey)
        grade = SupervisorAttendance.gradeTabs.contains(stored) ? stored : SupervisorAttendance.gradeTabs[0]
        super.init(style: .insetGrouped)
        title = "Điểm danh"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .always
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.register(HomeroomBannerCell.self, forCellReuseIdentifier: HomeroomBannerCell.reuseIdentifier)
        tableView.register(AttendanceSaveCell.self, forCellReuseIdentifier: AttendanceSaveCell.reuseIdentifier)
        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại danh sách lớp"
        refreshControl?.addAction(UIAction { [weak self] _ in self?.pullToRefresh() }, for: .valueChanged)
        configureHeader()
        render()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning to the tab refreshes in place; unsaved ticks in the open class are kept.
        if roster != nil, !saving { load(silently: true) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        if header.frame.size != size {
            header.frame.size = size
            tableView.tableHeaderView = header
        }
    }

    /// Runs `action` right away, or after the user agrees to drop unsaved ticks (web `guard`).
    func confirmDiscardIfNeeded(onCancel: (() -> Void)? = nil, then action: @escaping () -> Void) {
        guard hasUnsavedChanges else { action(); return }
        let alert = UIAlertController(title: "Bỏ thay đổi?", message: SupervisorAttendance.unsavedPrompt, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tiếp tục sửa", style: .cancel) { _ in onCancel?() })
        alert.addAction(UIAlertAction(title: "Bỏ thay đổi", style: .destructive) { [weak self] _ in
            self?.discardDraft()
            action()
        })
        present(alert, animated: true)
    }

    // MARK: - Header

    private func configureHeader() {
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        dayNavigator.presenter = self
        dayNavigator.onChange = { [weak self] selected in self?.chooseDate(selected) }
        todayButton.setTitle("Về hôm nay", for: .normal)
        todayButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        todayButton.titleLabel?.adjustsFontForContentSizeCategory = true
        todayButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        todayButton.addAction(UIAction { [weak self] _ in
            guard let self, let today = self.roster?.today else { return }
            self.chooseDate(today)
        }, for: .touchUpInside)
        dateRow.addArrangedSubview(dayNavigator)
        dateRow.addArrangedSubview(todayButton)
        dateRow.axis = .vertical
        dateRow.alignment = .leading
        dateRow.spacing = 4
        dateRow.isHidden = true

        gradeControl.selectedSegmentIndex = SupervisorAttendance.gradeTabs.firstIndex(of: grade) ?? 0
        gradeControl.accessibilityLabel = "Chọn khối"
        gradeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        gradeControl.addAction(UIAction { [weak self] _ in self?.gradeChanged() }, for: .valueChanged)

        noteLabel.text = SupervisorAttendance.excelNote
        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [subtitleLabel, dateRow, gradeControl, noteLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20)
        tableView.tableHeaderView = stack
    }

    private func updateHeader() {
        let date = roster?.date ?? requestedDate ?? VietnamDate.today()
        subtitleLabel.text = SupervisorAttendance.headerSubtitle(roster, date: date)
        let canChoose = roster?.canChooseDate == true
        dateRow.isHidden = !canChoose
        dayNavigator.setDate(date)
        todayButton.isHidden = !canChoose || roster.map { $0.date == $0.today } ?? true
        for (index, value) in SupervisorAttendance.gradeTabs.enumerated() {
            let title = SupervisorAttendance.gradeTabTitle(roster, grade: value)
            gradeControl.setTitle(title, forSegmentAt: index)
        }
        gradeControl.selectedSegmentIndex = SupervisorAttendance.gradeTabs.firstIndex(of: grade) ?? 0
        gradeControl.isEnabled = !saving
        view.setNeedsLayout()
    }

    // MARK: - Actions

    private func gradeChanged() {
        let next = SupervisorAttendance.gradeTabs[max(0, gradeControl.selectedSegmentIndex)]
        guard next != grade else { return }
        let previous = grade
        guard !saving else { gradeControl.selectedSegmentIndex = SupervisorAttendance.gradeTabs.firstIndex(of: previous) ?? 0; return }
        confirmDiscardIfNeeded(onCancel: { [weak self] in
            self?.gradeControl.selectedSegmentIndex = SupervisorAttendance.gradeTabs.firstIndex(of: previous) ?? 0
        }) { [weak self] in
            guard let self else { return }
            grade = next
            UserDefaults.standard.set(next, forKey: Self.gradeKey)
            closeClass()
            render()
        }
    }

    private func chooseDate(_ value: String) {
        guard let roster, roster.canChooseDate, !saving else { updateHeader(); return }
        let next = SupervisorAttendance.clampDate(value, today: roster.today)
        guard next != roster.date else { updateHeader(); return }
        confirmDiscardIfNeeded(onCancel: { [weak self] in self?.updateHeader() }) { [weak self] in
            guard let self else { return }
            requestedDate = next
            closeClass()
            self.roster = nil
            load()
        }
    }

    private func pullToRefresh() {
        guard !saving else { refreshControl?.endRefreshing(); return }
        confirmDiscardIfNeeded(onCancel: { [weak self] in self?.refreshControl?.endRefreshing() }) { [weak self] in
            self?.load()
        }
    }

    private func toggleClass(_ klass: AttendanceClass) {
        guard !saving else { return }
        confirmDiscardIfNeeded { [weak self] in
            guard let self else { return }
            if openClassId == klass.id {
                closeClass()
            } else {
                openClassId = klass.id
                draft = AttendanceClassDraft(klass)
                saveError = nil
                saveSuccess = nil
            }
            render()
            if let section = sectionIndex(of: klass.id) {
                tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
    }

    private func toggleStudent(_ student: AttendanceStudent, in klass: AttendanceClass) {
        guard !saving, openClassId == klass.id, draft?.classId == klass.id else { return }
        draft?.toggle(student.id)
        saveSuccess = nil
        saveError = nil
        guard let section = sectionIndex(of: klass.id) else { render(); return }
        let items = self.items(for: klass)
        let rows = items.indices.filter {
            switch items[$0] {
            case let .student(_, row, _): return row.id == student.id
            case .saveBar: return true
            default: return false
            }
        }
        tableView.reloadRows(at: rows.map { IndexPath(row: $0, section: section) }, with: .none)
        let absent = draft?.isAbsent(student.id) == true
        UIAccessibility.post(notification: .announcement, argument: "\(student.fullName): \(absent ? "vắng" : "có mặt")")
    }

    private func save(_ klass: AttendanceClass) {
        guard !saving, let draft, draft.classId == klass.id, let date = roster?.date else { return }
        saving = true
        saveError = nil
        saveSuccess = nil
        render()
        let version = generation
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await repository.saveClass(date: date, draft: draft)
                guard generation == version, openClassId == klass.id else { saving = false; render(); return }
                saving = false
                self.draft?.markSaved()
                saveSuccess = SupervisorAttendance.saveSuccessMessage(className: klass.displayName, result: result)
                UIAccessibility.post(notification: .announcement, argument: saveSuccess)
                render()
                load(silently: true)
            } catch is CancellationError {
                saving = false
                render()
            } catch {
                saving = false
                saveError = error.localizedDescription
                render()
                UIAccessibility.post(notification: .announcement, argument: saveError)
            }
        }
    }

    private func closeClass() {
        openClassId = nil
        draft = nil
        saveError = nil
        saveSuccess = nil
    }

    private func discardDraft() {
        guard let openClassId, let klass = SupervisorAttendance.classes(roster, grade: grade).first(where: { $0.id == openClassId }) else {
            draft = nil
            return
        }
        draft = AttendanceClassDraft(klass)
    }

    // MARK: - Loading

    private func load(silently: Bool = false) {
        guard session.canSeeAttendance else { refreshControl?.endRefreshing(); render(); return }
        loadTask?.cancel()
        generation += 1
        let version = generation
        let date = requestedDate
        loading = true
        loadError = nil
        if !silently { render() }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await repository.roster(date: date)
                guard !Task.isCancelled, generation == version else { return }
                loading = false
                roster = result
                requestedDate = result.date
                reconcileOpenClass()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == version else { return }
                loading = false
                loadError = error.localizedDescription
                if !silently { roster = nil; closeClass() }
            }
            refreshControl?.endRefreshing()
            render()
        }
    }

    /// Keep the open class after a refresh; rebuild its draft from server truth unless it has unsaved ticks.
    private func reconcileOpenClass() {
        guard let openClassId else { return }
        guard let klass = SupervisorAttendance.classes(roster, grade: grade).first(where: { $0.id == openClassId }) else {
            closeClass()
            return
        }
        if draft?.isDirty != true { draft = AttendanceClassDraft(klass) }
    }

    // MARK: - Rendering

    private func render() {
        var result: [Section] = []
        var status: [StatusRow] = []
        let date = roster?.date ?? requestedDate ?? VietnamDate.today()
        if !session.canSeeAttendance {
            status.append(.banner("Không có quyền", "Chỉ Giám thị hoặc Admin/Mod mới được điểm danh.", .danger, "lock"))
        } else if loading, roster == nil {
            status.append(.info("Đang tải danh sách lớp…", nil))
        } else if let loadError, roster == nil {
            status.append(.banner("Chưa tải được danh sách lớp", "\(loadError)\nKéo xuống để thử lại.", .danger, "exclamationmark.triangle"))
        } else if let roster {
            if let loadError {
                status.append(.banner("Chưa làm mới được", "\(loadError)\nKéo xuống để thử lại.", .warning, "exclamationmark.triangle"))
            }
            if roster.schoolYear == nil {
                status.append(.banner("Ngày \(VietnamDate.display(date)) không thuộc năm học nào.", "Quản trị viên tạo năm học trong Thiết lập tối cao › Thiết lập năm học.", .neutral, "calendar"))
            } else {
                if !roster.schoolDay.isSchoolDay {
                    let note = roster.schoolDay.note.isEmpty ? "Theo lịch, hôm nay không phải ngày học." : roster.schoolDay.note
                    status.append(.banner("Không phải ngày học — vẫn có thể lưu điểm danh nếu cần.", note, .info, "calendar"))
                }
                let classes = SupervisorAttendance.classes(roster, grade: grade)
                if classes.isEmpty {
                    status.append(.info("Chưa có lớp khối \(grade) đang hoạt động.", nil))
                }
                if !status.isEmpty { result.append(.status(status)) }
                result += classes.map { .klass($0) }
                sections = result
                updateHeader()
                tableView.reloadData()
                return
            }
        }
        if !status.isEmpty { result.append(.status(status)) }
        sections = result
        updateHeader()
        tableView.reloadData()
    }

    private func sectionIndex(of classId: String) -> Int? {
        sections.firstIndex { if case let .klass(klass) = $0 { klass.id == classId } else { false } }
    }

    private func items(for klass: AttendanceClass) -> [Item] {
        guard openClassId == klass.id else { return [.header(klass)] }
        guard !klass.students.isEmpty else { return [.header(klass), .empty] }
        return [.header(klass)] + klass.students.enumerated().map { .student(klass, $0.element, $0.offset) } + [.saveBar(klass)]
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case let .status(rows): return rows.count
        case let .klass(klass): return items(for: klass).count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case let .status(rows):
            switch rows[indexPath.row] {
            case let .info(title, detail):
                return infoCell(title: title, detail: detail)
            case let .banner(title, message, tone, symbol):
                let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
                cell.configure(title: title, message: message, tone: tone, symbol: symbol)
                return cell
            }
        case let .klass(klass):
            switch items(for: klass)[indexPath.row] {
            case .header: return classHeaderCell(klass)
            case let .student(_, student, index): return studentCell(student, index: index)
            case .empty: return infoCell(title: "Lớp chưa có học sinh vào ngày này.", detail: nil)
            case .saveBar:
                let cell = tableView.dequeueReusableCell(withIdentifier: AttendanceSaveCell.reuseIdentifier, for: indexPath) as! AttendanceSaveCell
                let absent = draft?.absentCount ?? 0
                cell.configure(
                    summary: draft?.summary ?? "",
                    buttonTitle: SupervisorAttendance.saveButtonTitle(className: klass.displayName, absentCount: absent, busy: saving),
                    busy: saving,
                    error: saveError,
                    success: saveSuccess
                )
                cell.onSave = { [weak self] in self?.save(klass) }
                return cell
            }
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case let .klass(klass) = sections[indexPath.section] else { return }
        switch items(for: klass)[indexPath.row] {
        case .header: toggleClass(klass)
        case let .student(_, student, _): toggleStudent(student, in: klass)
        default: break
        }
    }

    // MARK: - Cells

    private func infoCell(title: String, detail: String?) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "info") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "info")
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.secondaryText = detail
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none
        return cell
    }

    private func classHeaderCell(_ klass: AttendanceClass) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "classHeader") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "classHeader")
        let open = openClassId == klass.id
        var content = cell.defaultContentConfiguration()
        content.text = "Lớp \(klass.displayName)"
        content.secondaryText = "Sĩ số \(klass.students.count)"
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let statusText = SupervisorAttendance.classStatusText(klass.saved)
        let chip = HomeroomChipLabel(HomeroomChip(text: statusText, tone: klass.saved == nil ? .warning : .success))
        let chevron = UIImageView(image: UIImage(systemName: open ? "chevron.up" : "chevron.down"))
        chevron.tintColor = .secondaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        let accessory = UIStackView(arrangedSubviews: [chip, chevron])
        accessory.axis = .horizontal
        accessory.spacing = 8
        accessory.alignment = .center
        accessory.frame.size = accessory.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        cell.accessoryView = accessory
        cell.selectionStyle = saving ? .none : .default
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = "Lớp \(klass.displayName), sĩ số \(klass.students.count), \(statusText)"
        cell.accessibilityValue = open ? "Đang mở" : "Đã thu gọn"
        cell.accessibilityHint = open ? "Thu gọn danh sách học sinh" : "Mở danh sách học sinh để điểm danh"
        cell.accessibilityTraits = .button
        return cell
    }

    private func studentCell(_ student: AttendanceStudent, index: Int) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "student") ?? UITableViewCell(style: .default, reuseIdentifier: "student")
        let absent = draft?.isAbsent(student.id) == true
        let number = student.rosterNumber.map(String.init) ?? String(index + 1)
        var content = cell.defaultContentConfiguration()
        content.text = "\(number). \(student.fullName)"
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content

        let danger = HomeroomPalette.colors(.danger)
        let box = UIImageView(image: UIImage(systemName: absent ? "checkmark.square.fill" : "square"))
        box.tintColor = absent ? danger.text : .secondaryLabel
        box.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3)
        let label = UILabel()
        label.text = "Vắng"
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = absent ? danger.text : .label
        let accessory = UIStackView(arrangedSubviews: [box, label])
        accessory.axis = .horizontal
        accessory.spacing = 6
        accessory.alignment = .center
        accessory.frame.size = accessory.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        cell.accessoryView = accessory

        var background = UIBackgroundConfiguration.listCell()
        if absent { background.backgroundColor = danger.background }
        cell.backgroundConfiguration = background
        cell.selectionStyle = saving ? .none : .default
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = "\(number). \(student.fullName)"
        cell.accessibilityValue = absent ? "Vắng" : "Có mặt"
        cell.accessibilityHint = absent ? "Bỏ đánh dấu vắng" : "Đánh dấu vắng"
        cell.accessibilityTraits = absent ? [.button, .selected] : .button
        return cell
    }
}

/// Count summary, inline error/success and the one primary action "Lưu lớp {tên}".
final class AttendanceSaveCell: UITableViewCell {
    static let reuseIdentifier = "attendance-save"
    var onSave: (() -> Void)?
    private let summary = UILabel()
    private let errorLabel = UILabel()
    private let successLabel = UILabel()
    private let button = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        summary.font = .preferredFont(forTextStyle: .subheadline)
        summary.adjustsFontForContentSizeCategory = true
        summary.textColor = .secondaryLabel
        summary.numberOfLines = 0
        for (label, tone) in [(errorLabel, HomeroomTone.danger), (successLabel, HomeroomTone.success)] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = HomeroomPalette.colors(tone).text
            label.numberOfLines = 0
        }
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = HomeroomPalette.primaryBackground
        configuration.baseForegroundColor = HomeroomPalette.primaryForeground
        configuration.showsActivityIndicator = false
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .headline)
            return outgoing
        }
        button.configuration = configuration
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.onSave?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [summary, errorLabel, successLabel, button])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(summary text: String, buttonTitle: String, busy: Bool, error: String?, success: String?) {
        summary.text = text
        errorLabel.text = error
        errorLabel.isHidden = error?.isEmpty ?? true
        successLabel.text = success
        successLabel.isHidden = success?.isEmpty ?? true
        button.configuration?.title = buttonTitle
        button.configuration?.showsActivityIndicator = busy
        button.isEnabled = !busy
        button.accessibilityLabel = buttonTitle
    }
}

/// When an account has both Lớp chủ nhiệm and Điểm danh (admin/mod, or a GVCN who is also Giám thị), one
/// "Học sinh" tab holds both so the tab bar stays at five items (no system "More" tab).
@MainActor
final class StudentsHubViewController: UIViewController {
    private let homeroom: UIViewController
    private let attendance: AttendanceViewController

    init(homeroom: UIViewController, attendance: AttendanceViewController) {
        self.homeroom = homeroom
        self.attendance = attendance
        super.init(nibName: nil, bundle: nil)
        title = "Học sinh"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always
        let attendanceButton = hubButton(
            title: "Điểm danh",
            subtitle: "Giám thị điểm danh từng lớp theo ngày",
            systemImage: "checklist"
        ) { [weak self] in self?.open(self?.attendance) }
        let homeroomButton = hubButton(
            title: "Lớp chủ nhiệm",
            subtitle: "Tổng quan lớp, học sinh vắng và hồ sơ học sinh",
            systemImage: "person.3"
        ) { [weak self] in self?.open(self?.homeroom) }
        let stack = UIStackView(arrangedSubviews: [attendanceButton, homeroomButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.distribution = .fillEqually
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            attendanceButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 132),
        ])
    }

    private func open(_ controller: UIViewController?) {
        guard let controller, let navigationController else { return }
        if navigationController.viewControllers.contains(controller) {
            navigationController.popToViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            navigationController.popToRootViewController(animated: false)
            navigationController.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func hubButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = .secondarySystemGroupedBackground
        configuration.baseForegroundColor = .label
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .top
        configuration.imagePadding = 10
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .headline)
            return outgoing
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .footnote)
            outgoing.foregroundColor = .secondaryLabel
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 16, bottom: 22, trailing: 16)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = title
        button.accessibilityHint = subtitle
        return button
    }
}
