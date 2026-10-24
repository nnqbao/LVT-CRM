import UIKit

// Lớp học › Tổng quan, Lớp giảng dạy and the Sổ đầu bài sheet (web src/teaching/TeachingViews.jsx).

// MARK: - Tổng quan

@MainActor
final class TeachingOverviewViewController: UITableViewController, TeachingYearSection {
    private enum Row {
        case message(String, String?)
        case lesson(Lesson, logged: Bool)
        case absenceSummary(TeachingAbsenceOverview)
        case absenceClass(TeachingAbsenceOverview.ClassRow)
        case link(String, ClassesHubViewController.Section)
    }

    private let teachingRepository: TeachingRepository
    private let homeroomRepository: HomeroomRepository
    private let openSection: (ClassesHubViewController.Section) -> Void
    private var year: SchoolYear?
    private var teaching: MyTeaching?
    private var catalog: TeachingCatalog?
    private var absences: TeachingAbsenceOverview?
    private var teachingError: String?
    private var absenceError: String?
    private var loading = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lessonRows: [Row] = []
    private var absenceRows: [Row] = []
    private var today = TeachingSchedule.vietnamNow().date

    init(teachingRepository: TeachingRepository, homeroomRepository: HomeroomRepository, openSection: @escaping (ClassesHubViewController.Section) -> Void) {
        self.teachingRepository = teachingRepository
        self.homeroomRepository = homeroomRepository
        self.openSection = openSection
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(TeachingCell.self, forCellReuseIdentifier: TeachingCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(reload))]
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if year != nil { reload() }
    }

    func apply(year: SchoolYear?) {
        guard year?.id != self.year?.id || teaching == nil else { return }
        self.year = year
        if isViewLoaded, view.window != nil || teaching == nil { reload() }
    }

    @objc private func reload() {
        task?.cancel()
        generation += 1
        let version = generation
        guard let year else {
            loading = false
            teaching = nil
            absences = nil
            refreshControl?.endRefreshing()
            render()
            return
        }
        today = TeachingSchedule.vietnamNow().date
        let date = today
        loading = true
        teachingError = nil
        absenceError = nil
        render()
        let repository = teachingRepository
        task = Task { [weak self] in
            async let teachingResult = Self.capture { try await repository.myTeaching(yearId: year.id) }
            async let catalogResult = Self.capture { try await repository.catalog() }
            async let absenceResult = Self.capture { try await repository.absenceOverview(yearId: year.id, date: date) }
            let (loadedTeaching, loadedCatalog, loadedAbsences) = await (teachingResult, catalogResult, absenceResult)
            guard let self, !Task.isCancelled, generation == version else { return }
            loading = false
            switch (loadedTeaching, loadedCatalog) {
            case let (.success(data), .success(names)):
                teaching = data
                catalog = names
            case let (.failure(error), _), let (_, .failure(error)):
                teaching = nil
                teachingError = TeachingText.message(error)
            }
            switch loadedAbsences {
            case .success(let data): absences = data
            case .failure(let error):
                absences = nil
                absenceError = TeachingText.message(error)
            }
            refreshControl?.endRefreshing()
            render()
        }
    }

    private nonisolated static func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    private func render() {
        lessonRows = []
        absenceRows = []
        if year == nil {
            lessonRows = []
        } else if loading, teaching == nil {
            lessonRows = [.message("Đang tải tiết dạy…", nil)]
        } else if let teachingError {
            lessonRows = [.message("Chưa tải được tiết dạy", "\(teachingError)\nKéo xuống để thử lại.")]
        } else if let teaching {
            let lessons = TeachingSchedule.expandLessons(teaching.slots, from: today, to: today, year: teaching.year, holidays: teaching.holidays)
            let logged = Set(teaching.todayLogs.filter { $0.date == today }.map { "\($0.classId)-\($0.session)-\($0.period)" })
            if lessons.isEmpty {
                lessonRows = [.message(
                    "Hôm nay bạn không có tiết dạy.",
                    teaching.slots.isEmpty ? "Bạn chưa được xếp lịch dạy trong năm học này." : "Xem lịch các ngày khác ở mục Lịch dạy."
                )]
            } else {
                lessonRows = lessons.map { .lesson($0, logged: logged.contains("\($0.classId)-\($0.session)-\($0.period)")) }
            }
            lessonRows.append(.link("Xem lớp giảng dạy", .teaching))
        }

        if year == nil {
            absenceRows = []
        } else if loading, absences == nil {
            absenceRows = [.message("Đang tải điểm danh…", nil)]
        } else if let absenceError {
            absenceRows = [.message("Chưa tải được điểm danh", absenceError)]
        } else if let absences {
            if absences.schoolWide {
                absenceRows = [.absenceSummary(absences)]
            } else if absences.classes.isEmpty {
                absenceRows = [.message("Bạn không chủ nhiệm lớp nào trong năm học này.", nil)]
            } else {
                absenceRows = absences.classes.map { .absenceClass($0) }
            }
            absenceRows.append(.link("Xem lớp chủ nhiệm", .homeroom))
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { year == nil ? 0 : absenceRows.isEmpty ? 1 : 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? lessonRows.count : absenceRows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0
            ? "Tiết dạy hôm nay · \(TeachingSchedule.weekdayLabel(today)), \(TeachingSchedule.displayDate(today))"
            : "Học sinh vắng hôm nay"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 && absences?.schoolWide == false && absences?.classes.isEmpty == false
            ? "Vào lớp để đánh dấu vắng có phép hay không phép."
            : nil
    }

    private func row(at indexPath: IndexPath) -> Row? {
        let rows = indexPath.section == 0 ? lessonRows : absenceRows
        return indexPath.row < rows.count ? rows[indexPath.row] : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TeachingCell.reuseIdentifier, for: indexPath) as! TeachingCell
        switch row(at: indexPath) {
        case let .message(title, detail)?:
            cell.configure(title: title, subtitle: detail, tappable: false)
        case let .lesson(lesson, logged)?:
            let className = teaching?.className(lesson.classId) ?? "Lớp"
            let subject = catalog?.subjectName(lesson.subjectId) ?? "Môn học"
            cell.configure(
                leading: TeachingSchedule.lessonStartTime(lesson),
                title: "\(className) · \(subject)",
                subtitle: TeachingSchedule.periodLabel(lesson),
                chips: [HomeroomChip(text: logged ? "Đã ghi sổ" : "Chưa ghi sổ", tone: logged ? .success : .warning)],
                tappable: true
            )
            cell.accessibilityHint = "Mở Sổ đầu bài của tiết này"
        case let .absenceSummary(overview)?:
            let saved = overview.classes.filter(\.saved).count
            cell.configure(
                title: "Toàn trường có \(overview.absent) học sinh vắng",
                subtitle: "\(overview.excused) có phép · \(overview.unexcused) không phép",
                detail: "\(saved)/\(overview.classes.count) lớp đã được điểm danh.",
                tappable: false
            )
        case let .absenceClass(row)?:
            let chip: HomeroomChip = !row.saved
                ? HomeroomChip(text: "Chưa điểm danh", tone: .neutral)
                : row.absent > 0 ? HomeroomChip(text: "\(row.absent) vắng", tone: .danger) : HomeroomChip(text: "Đủ", tone: .success)
            cell.configure(
                title: row.name,
                subtitle: row.saved ? "\(row.absent) em vắng" : "Chưa điểm danh",
                detail: row.saved
                    ? "\(row.excused) có phép · \(row.unexcused) không phép · sĩ số \(row.rosterCount)"
                    : "Sĩ số \(row.rosterCount)",
                chips: [chip],
                tappable: true
            )
            cell.accessibilityHint = "Mở điểm danh của lớp"
        case let .link(title, _)?:
            cell.configure(title: title, tappable: true)
            cell.accessibilityHint = nil
        case nil:
            cell.configure(title: "", tappable: false)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(at: indexPath) {
        case let .lesson(lesson, _)?:
            guard let teaching, let klass = teaching.classes.first(where: { $0.id == lesson.classId }) else { return }
            let form = LessonLogViewController(
                repository: teachingRepository, teachingClass: klass, data: teaching,
                subjectName: { [catalog] in catalog?.subjectName($0) ?? "Môn học" },
                initialDate: lesson.date, initialLesson: lesson
            )
            form.onSaved = { [weak self] in self?.reload() }
            present(UINavigationController(rootViewController: form), animated: true)
        case let .absenceClass(row)?:
            guard let year else { return }
            let context = DetailContext(yearId: year.id, classId: row.id, date: today, from: year.startDate, to: year.endDate)
            navigationController?.pushViewController(HomeroomDetailViewController(repository: homeroomRepository, context: context), animated: true)
        case let .link(_, section)?:
            openSection(section)
        default:
            break
        }
    }
}

// MARK: - Lớp giảng dạy

@MainActor
final class TeachingClassesViewController: UITableViewController, TeachingYearSection {
    private let repository: TeachingRepository
    private var year: SchoolYear?
    private var data: MyTeaching?
    private var catalog: TeachingCatalog?
    private var rows: [TeachingSchedule.ClassRow] = []
    private var errorMessage: String?
    private var loading = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var now = TeachingSchedule.vietnamNow()

    init(repository: TeachingRepository) {
        self.repository = repository
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(TeachingCell.self, forCellReuseIdentifier: TeachingCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(reload))]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if year != nil { reload() }
    }

    func apply(year: SchoolYear?) {
        guard year?.id != self.year?.id || data == nil else { return }
        self.year = year
        if isViewLoaded { reload() }
    }

    @objc private func reload() {
        task?.cancel()
        generation += 1
        let version = generation
        guard let year else {
            data = nil
            rows = []
            refreshControl?.endRefreshing()
            tableView.reloadData()
            return
        }
        loading = true
        errorMessage = nil
        if data == nil { tableView.reloadData() }
        let repository = self.repository
        task = Task { [weak self] in
            do {
                async let loaded = repository.myTeaching(yearId: year.id)
                async let names = repository.catalog()
                let (teaching, subjects) = try await (loaded, names)
                guard let self, !Task.isCancelled, generation == version else { return }
                data = teaching
                catalog = subjects
                now = TeachingSchedule.vietnamNow()
                rows = TeachingSchedule.teachingClassRows(teaching, now: now)
            } catch {
                guard let self, !Task.isCancelled, generation == version else { return }
                data = nil
                rows = []
                errorMessage = TeachingText.message(error)
            }
            guard let self, generation == version else { return }
            loading = false
            refreshControl?.endRefreshing()
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(rows.count, 1) }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        rows.isEmpty ? nil : "Bấm vào lớp để ghi Sổ đầu bài cho tiết vừa dạy. Giáo viên chủ nhiệm của lớp sẽ thấy đánh giá này."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TeachingCell.reuseIdentifier, for: indexPath) as! TeachingCell
        guard indexPath.row < rows.count else {
            if year == nil {
                cell.configure(title: "Chưa có năm học", tappable: false)
            } else if loading {
                cell.configure(title: "Đang tải lớp giảng dạy…", tappable: false)
            } else if let errorMessage {
                cell.configure(title: "Chưa tải được lớp giảng dạy", subtitle: "\(errorMessage)\nKéo xuống để thử lại.", tappable: false)
            } else {
                cell.configure(
                    title: "Bạn chưa được xếp lịch dạy trong năm học này.",
                    subtitle: "Quản trị viên xếp lịch tại Thiết lập giáo viên hoặc Thiết lập lịch dạy.",
                    tappable: false
                )
            }
            return cell
        }
        let row = rows[indexPath.row]
        let isToday = row.next?.date == now.date
        cell.configure(
            title: row.teachingClass.name,
            subtitle: row.subjectIds.map { catalog?.subjectName($0) ?? "Môn học" }.joined(separator: ", "),
            detail: TeachingSchedule.nextLessonText(row.next, today: now.date),
            chips: isToday ? [HomeroomChip(text: "Hôm nay", tone: .info)] : [],
            tappable: true
        )
        cell.accessibilityHint = "Mở Sổ đầu bài"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < rows.count, let data else { return }
        let form = LessonLogViewController(
            repository: repository, teachingClass: rows[indexPath.row].teachingClass, data: data,
            subjectName: { [catalog] in catalog?.subjectName($0) ?? "Môn học" },
            initialDate: TeachingSchedule.latestLogDate(today: TeachingSchedule.vietnamNow().date, year: data.year), initialLesson: nil
        )
        form.onSaved = { [weak self] in self?.reload() }
        present(UINavigationController(rootViewController: form), animated: true)
    }
}

// MARK: - Sổ đầu bài sheet

/// Ngày dạy (≤ today, inside the year) → Tiết (the teacher's lessons in this class that day) → 1–5 sao → nhận xét → Lưu.
@MainActor
final class LessonLogViewController: UIViewController, UITextViewDelegate {
    var onSaved: (() -> Void)?

    private let repository: TeachingRepository
    private let teachingClass: TeachingClass
    private let data: MyTeaching
    private let subjectName: (String) -> String
    private var date: String
    private var lessons: [Lesson] = []
    private var current: Lesson?
    private var pickedKey: String?
    private var saved: [LessonLogRecord] = []
    private var savedLoading = false
    private var saving = false
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let subtitleLabel = UILabel()
    private let datePicker = UIDatePicker()
    private let lessonButton = UIButton(type: .system)
    private let noLessonLabel = UILabel()
    private let savedLabel = UILabel()
    private let stars = StarRatingControl()
    private let commentView = UITextView()
    private let counterLabel = UILabel()
    private let lockedLabel = UILabel()
    private let errorLabel = UILabel()
    private lazy var saveItem = UIBarButtonItem(title: "Lưu", style: .prominent, target: self, action: #selector(save))

    init(repository: TeachingRepository, teachingClass: TeachingClass, data: MyTeaching, subjectName: @escaping (String) -> String, initialDate: String, initialLesson: Lesson?) {
        self.repository = repository
        self.teachingClass = teachingClass
        self.data = data
        self.subjectName = subjectName
        let latest = TeachingSchedule.latestLogDate(today: TeachingSchedule.vietnamNow().date, year: data.year)
        date = min(max(initialDate, data.year.startDate), latest)
        pickedKey = initialLesson?.cellKey
        super.init(nibName: nil, bundle: nil)
        title = "Sổ đầu bài · \(teachingClass.name)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Đóng", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = saveItem
        isModalInPresentation = true

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        style(subtitleLabel, .subheadline, color: .secondaryLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(16, after: subtitleLabel)

        stack.addArrangedSubview(fieldLabel("Ngày dạy"))
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.calendar = Calendar(identifier: .gregorian)
        datePicker.timeZone = VietnamDate.timeZone
        datePicker.locale = Locale(identifier: "vi_VN")
        datePicker.minimumDate = VietnamDate.date(from: data.year.startDate)
        datePicker.maximumDate = VietnamDate.date(from: TeachingSchedule.latestLogDate(today: TeachingSchedule.vietnamNow().date, year: data.year))
        datePicker.date = VietnamDate.date(from: date) ?? Date()
        datePicker.contentHorizontalAlignment = .leading
        datePicker.accessibilityLabel = "Ngày dạy"
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        stack.addArrangedSubview(datePicker)
        stack.setCustomSpacing(16, after: datePicker)

        stack.addArrangedSubview(fieldLabel("Tiết"))
        var lessonConfiguration = UIButton.Configuration.gray()
        lessonConfiguration.cornerStyle = .medium
        lessonConfiguration.titleAlignment = .leading
        lessonConfiguration.image = UIImage(systemName: "chevron.up.chevron.down")
        lessonConfiguration.imagePlacement = .trailing
        lessonConfiguration.imagePadding = 8
        lessonButton.configuration = lessonConfiguration
        lessonButton.contentHorizontalAlignment = .leading
        lessonButton.showsMenuAsPrimaryAction = true
        lessonButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(lessonButton)
        style(noLessonLabel, .footnote, color: HomeroomPalette.colors(.info).text)
        noLessonLabel.text = "Ngày này bạn không có tiết ở lớp này. Chọn ngày khác có tiết dạy để ghi sổ."
        stack.addArrangedSubview(noLessonLabel)
        style(savedLabel, .footnote, color: HomeroomPalette.colors(.success).text)
        stack.addArrangedSubview(savedLabel)
        stack.setCustomSpacing(16, after: savedLabel)

        stack.addArrangedSubview(fieldLabel("Đánh giá tiết học"))
        stars.addTarget(self, action: #selector(ratingChanged), for: .valueChanged)
        stack.addArrangedSubview(stars)
        stack.setCustomSpacing(16, after: stars)

        stack.addArrangedSubview(fieldLabel("Nhận xét tiết học"))
        commentView.font = .preferredFont(forTextStyle: .body)
        commentView.adjustsFontForContentSizeCategory = true
        commentView.backgroundColor = .secondarySystemGroupedBackground
        commentView.layer.cornerRadius = 10
        commentView.layer.cornerCurve = .continuous
        commentView.layer.borderColor = UIColor.separator.cgColor
        commentView.layer.borderWidth = 1
        commentView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        commentView.isScrollEnabled = false
        commentView.delegate = self
        commentView.accessibilityLabel = "Nhận xét tiết học"
        commentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.addArrangedSubview(commentView)
        style(counterLabel, .caption1, color: .secondaryLabel)
        counterLabel.textAlignment = .right
        stack.addArrangedSubview(counterLabel)

        style(lockedLabel, .footnote, color: HomeroomPalette.colors(.warning).text)
        lockedLabel.text = "Năm học đã khóa — không ghi thêm Sổ đầu bài."
        lockedLabel.isHidden = !data.year.locked
        stack.addArrangedSubview(lockedLabel)
        style(errorLabel, .footnote, color: .systemRed)
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        refreshLessons()
    }

    private func style(_ label: UILabel, _ textStyle: UIFont.TextStyle, color: UIColor) {
        label.font = .preferredFont(forTextStyle: textStyle)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
    }

    private func fieldLabel(_ text: String) -> UILabel {
        let label = UILabel()
        style(label, .subheadline, color: .label)
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        label.text = text
        return label
    }

    @objc private func close() {
        loadTask?.cancel()
        dismiss(animated: true)
    }

    @objc private func dateChanged() {
        let selected = VietnamDate.string(from: datePicker.date)
        guard selected != date else { return }
        date = selected
        pickedKey = nil
        refreshLessons()
    }

    private func refreshLessons() {
        lessons = TeachingSchedule.lessons(classId: teachingClass.id, date: date, data: data)
        saved = []
        selectLesson(resetForm: true)
        loadSaved()
    }

    private func selectLesson(resetForm: Bool) {
        let now = TeachingSchedule.vietnamNow()
        current = lessons.first { $0.cellKey == pickedKey } ?? TeachingSchedule.defaultLesson(lessons, date: date, now: now)
        lessonButton.menu = UIMenu(title: "Tiết", children: lessons.map { lesson in
            UIAction(
                title: "\(TeachingSchedule.periodLabel(lesson)) · \(TeachingSchedule.lessonStartTime(lesson))",
                subtitle: subjectName(lesson.subjectId),
                state: lesson.cellKey == current?.cellKey ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                pickedKey = lesson.cellKey
                selectLesson(resetForm: true)
            }
        })
        let lessonTitle = current.map { "\(TeachingSchedule.periodLabel($0)) · \(TeachingSchedule.lessonStartTime($0))" } ?? "Không có tiết"
        lessonButton.configuration?.title = lessonTitle
        lessonButton.isEnabled = !lessons.isEmpty
        lessonButton.accessibilityLabel = "Tiết, \(lessonTitle)"
        noLessonLabel.isHidden = !lessons.isEmpty
        subtitleLabel.text = current.map { "\(TeachingSchedule.periodLabel($0)) · \(subjectName($0.subjectId)) · \(TeachingSchedule.displayDate(date))" }
            ?? TeachingSchedule.displayDate(date)
        if resetForm {
            let record = savedRecord
            stars.value = record?.rating ?? 0
            commentView.text = record?.comment ?? ""
        }
        updateState()
    }

    private var savedRecord: LessonLogRecord? {
        guard let current else { return nil }
        return saved.first { $0.session == current.session && $0.period == current.period }
    }

    private func loadSaved() {
        loadTask?.cancel()
        generation += 1
        let version = generation
        let requestedDate = date
        savedLoading = true
        updateState()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let records = try await repository.myLogs(classId: teachingClass.id, date: requestedDate)
                guard !Task.isCancelled, generation == version else { return }
                saved = records
                savedLoading = false
                selectLesson(resetForm: true)
            } catch {
                guard !Task.isCancelled, generation == version else { return }
                savedLoading = false
                showError(TeachingText.message(error))
                updateState()
            }
        }
    }

    @objc private func ratingChanged() { updateState() }

    func textViewDidChange(_ textView: UITextView) { updateState() }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let next = (textView.text as NSString).replacingCharacters(in: range, with: text)
        return next.count <= 1000
    }

    private func updateState() {
        let locked = data.year.locked
        let editable = current != nil && !locked && !saving
        stars.isEnabled = editable
        commentView.isEditable = editable
        commentView.alpha = editable ? 1 : 0.6
        counterLabel.text = "\(commentView.text.count)/1000"
        if let record = savedRecord, let updatedAt = record.updatedAt {
            savedLabel.text = "Đã ghi lúc \(Self.timestamp(updatedAt)) — lưu lại để sửa."
            savedLabel.isHidden = false
        } else {
            savedLabel.isHidden = true
        }
        saveItem.isEnabled = editable && stars.value > 0 && !savedLoading
        saveItem.title = saving ? "Đang lưu…" : "Lưu"
    }

    private func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
        if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    @objc private func save() {
        guard let current, !saving else { return }
        let args: [String: Any]
        do {
            args = try TeachingPayload.lessonLog(classId: teachingClass.id, date: date, lesson: current, rating: stars.value, comment: commentView.text)
        } catch {
            showError(TeachingText.message(error))
            return
        }
        saving = true
        showError(nil)
        updateState()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.saveLog(args)
                saving = false
                UIAccessibility.post(notification: .announcement, argument: "Đã lưu Sổ đầu bài.")
                onSaved?()
                dismiss(animated: true)
            } catch {
                saving = false
                showError(TeachingText.message(error))
                updateState()
            }
        }
    }

    static func timestamp(_ milliseconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = VietnamDate.timeZone
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}

/// 1–5 stars. VoiceOver: one adjustable element ("3 trên 5 sao"), swipe up/down to change.
final class StarRatingControl: UIControl {
    var value: Int = 0 {
        didSet { updateStars() }
    }
    private let stack = UIStackView()
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        for star in 1...5 {
            let button = UIButton(type: .system)
            button.tintColor = .systemOrange
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.isAccessibilityElement = false
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.value = star
                self.sendActions(for: .valueChanged)
            }, for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        isAccessibilityElement = true
        accessibilityLabel = "Đánh giá tiết học"
        accessibilityTraits = .adjustable
        updateStars()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet {
            buttons.forEach { $0.isEnabled = isEnabled }
            accessibilityTraits = isEnabled ? .adjustable : [.adjustable, .notEnabled]
        }
    }

    private func updateStars() {
        let configuration = UIImage.SymbolConfiguration(textStyle: .title2)
        for (index, button) in buttons.enumerated() {
            button.setImage(UIImage(systemName: index < value ? "star.fill" : "star", withConfiguration: configuration), for: .normal)
        }
        accessibilityValue = value == 0 ? "Chưa chọn" : "\(value) trên 5 sao"
    }

    override func accessibilityIncrement() {
        guard isEnabled, value < 5 else { return }
        value += 1
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        guard isEnabled, value > 1 else { return }
        value -= 1
        sendActions(for: .valueChanged)
    }
}
