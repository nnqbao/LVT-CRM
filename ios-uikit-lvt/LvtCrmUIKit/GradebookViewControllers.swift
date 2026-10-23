import UIKit

// Lớp học › Học bạ (web src/teaching/Gradebook.jsx): lớp theo khối → học sinh → học bạ (điểm, ĐTB) → Thêm / sửa / xóa điểm.
// The server decides who sees which subject (`fullView`) and who may write (`writableSubjectIds`, `canEdit`).

@MainActor
final class GradebookClassesViewController: UITableViewController, TeachingYearSection {
    private let repository: TeachingRepository
    private var year: SchoolYear?
    private var groups: [(grade: Int, classes: [GradebookClassRow])] = []
    private var catalog: TeachingCatalog?
    private var loaded = false
    private var loading = false
    private var errorMessage: String?
    private var task: Task<Void, Never>?
    private var generation = 0

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
        tableView.estimatedRowHeight = 64
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(reload))]
    }

    func apply(year: SchoolYear?) {
        guard year?.id != self.year?.id || !loaded else { return }
        self.year = year
        if isViewLoaded { reload() }
    }

    @objc private func reload() {
        task?.cancel()
        generation += 1
        let version = generation
        guard let year else {
            groups = []
            refreshControl?.endRefreshing()
            tableView.reloadData()
            return
        }
        loading = true
        errorMessage = nil
        if !loaded { tableView.reloadData() }
        let repository = self.repository
        task = Task { [weak self] in
            do {
                async let classes = repository.gradebookClasses(yearId: year.id)
                async let names = repository.catalog()
                let (rows, subjects) = try await (classes, names)
                guard let self, !Task.isCancelled, generation == version else { return }
                groups = rows.isEmpty ? [] : GradebookLayout.groups(rows)
                catalog = subjects
                loaded = true
            } catch {
                guard let self, !Task.isCancelled, generation == version else { return }
                groups = []
                loaded = false
                errorMessage = TeachingText.message(error)
            }
            guard let self, generation == version else { return }
            loading = false
            refreshControl?.endRefreshing()
            tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { groups.isEmpty ? 1 : groups.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.isEmpty ? (year == nil ? 0 : 1) : max(groups[section].classes.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !groups.isEmpty else { return nil }
        let group = groups[section]
        return "Khối \(group.grade) · \(group.classes.count) lớp"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 && !groups.isEmpty
            ? "Chọn lớp rồi chọn học sinh để xem và nhập điểm. Bạn nhập điểm cho môn mình dạy ở lớp đó."
            : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TeachingCell.reuseIdentifier, for: indexPath) as! TeachingCell
        guard !groups.isEmpty else {
            if loading {
                cell.configure(title: "Đang tải lớp…", tappable: false)
            } else if let errorMessage {
                cell.configure(title: "Chưa tải được Học bạ", subtitle: "\(errorMessage)\nKéo xuống để thử lại.", tappable: false)
            } else {
                cell.configure(
                    title: "Bạn chưa phụ trách lớp nào trong năm học này.",
                    subtitle: "Học bạ hiện các lớp bạn được xếp lịch dạy hoặc làm giáo viên chủ nhiệm.",
                    tappable: false
                )
            }
            return cell
        }
        let group = groups[indexPath.section]
        guard indexPath.row < group.classes.count else {
            cell.configure(title: "Khối này chưa có lớp trong năm học.", tappable: false)
            return cell
        }
        let row = group.classes[indexPath.row]
        cell.configure(
            title: row.name,
            subtitle: GradebookLayout.classMeta(row) { [catalog] in catalog?.subjectName($0) ?? "Môn" },
            tappable: true
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !groups.isEmpty, indexPath.row < groups[indexPath.section].classes.count else { return }
        let row = groups[indexPath.section].classes[indexPath.row]
        navigationController?.pushViewController(GradebookStudentsViewController(repository: repository, classId: row.id, className: row.name), animated: true)
    }
}

@MainActor
final class GradebookStudentsViewController: UITableViewController {
    private let repository: TeachingRepository
    private let classId: String
    private var data: GradebookClassStudents?
    private var errorMessage: String?
    private var task: Task<Void, Never>?

    init(repository: TeachingRepository, classId: String, className: String) {
        self.repository = repository
        self.classId = classId
        super.init(style: .insetGrouped)
        title = className
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(TeachingCell.self, forCellReuseIdentifier: TeachingCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        reload()
    }

    @objc private func reload() {
        task?.cancel()
        errorMessage = nil
        let repository = self.repository, classId = self.classId
        task = Task { [weak self] in
            do {
                let loaded = try await repository.classStudents(classId: classId)
                guard let self, !Task.isCancelled else { return }
                data = loaded
                title = loaded.className
            } catch {
                guard let self, !Task.isCancelled else { return }
                errorMessage = TeachingText.message(error)
            }
            self?.refreshControl?.endRefreshing()
            self?.tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(data?.students.count ?? 0, 1) }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let data else { return nil }
        return "Học bạ · Năm học \(data.yearName) · \(data.students.count) học sinh"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TeachingCell.reuseIdentifier, for: indexPath) as! TeachingCell
        guard let data, indexPath.row < data.students.count else {
            if let errorMessage {
                cell.configure(title: "Chưa tải được học sinh", subtitle: errorMessage, tappable: false)
            } else if data == nil {
                cell.configure(title: "Đang tải học sinh…", tappable: false)
            } else {
                cell.configure(title: "Lớp chưa có học sinh.", tappable: false)
            }
            return cell
        }
        let student = data.students[indexPath.row]
        let number = String(student.rosterNumber ?? indexPath.row + 1)
        let birth = student.dateOfBirth.isEmpty ? "—" : TeachingSchedule.displayDate(student.dateOfBirth)
        cell.configure(
            leading: number,
            title: student.fullName,
            subtitle: "Mã HS \(student.studentCode) · Ngày sinh \(birth)",
            tappable: true,
            accessibilityLabel: "Số \(number), \(student.fullName), mã \(student.studentCode), ngày sinh \(birth)"
        )
        cell.accessibilityHint = "Mở học bạ"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let data, indexPath.row < data.students.count else { return }
        navigationController?.pushViewController(StudentRecordViewController(repository: repository, studentId: data.students[indexPath.row].id), animated: true)
    }
}

/// Học bạ của một học sinh: chips năm học (Khối · Lớp · ĐTB năm), mỗi môn HK I / HK II / Cả năm, dòng "ĐTB các môn".
@MainActor
final class StudentRecordViewController: UITableViewController {
    private let repository: TeachingRepository
    private let studentId: String
    private var yearId: String?
    private var record: StudentRecord?
    private var errorMessage: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private let headerStack = UIStackView()
    private lazy var addItem = UIBarButtonItem(title: "Thêm điểm", style: .plain, target: self, action: #selector(addScore))

    init(repository: TeachingRepository, studentId: String) {
        self.repository = repository
        self.studentId = studentId
        super.init(style: .insetGrouped)
        title = "Học bạ"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(TeachingCell.self, forCellReuseIdentifier: TeachingCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        headerStack.axis = .vertical
        headerStack.spacing = 8
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20)
        tableView.tableHeaderView = headerStack
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeTableHeader(tableView)
    }

    @objc private func reload() {
        task?.cancel()
        generation += 1
        let version = generation
        errorMessage = nil
        let repository = self.repository, studentId = self.studentId, yearId = self.yearId
        task = Task { [weak self] in
            do {
                let loaded = try await repository.studentRecord(studentId: studentId, yearId: yearId)
                guard let self, !Task.isCancelled, generation == version else { return }
                record = loaded
            } catch {
                guard let self, !Task.isCancelled, generation == version else { return }
                errorMessage = TeachingText.message(error)
            }
            guard let self, generation == version else { return }
            refreshControl?.endRefreshing()
            render()
        }
    }

    private func render() {
        headerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        navigationItem.rightBarButtonItem = record?.canAddScore == true ? addItem : nil
        if let record {
            let name = makeLabel(record.fullName, .title2, weight: .bold)
            name.accessibilityTraits = .header
            headerStack.addArrangedSubview(name)
            var meta = "Mã HS \(record.studentCode)"
            if !record.dateOfBirth.isEmpty { meta += " · Ngày sinh \(TeachingSchedule.displayDate(record.dateOfBirth))" }
            if let year = record.selectedYear { meta += " · \(year.className.isEmpty ? "Lớp" : year.className) · Năm học \(year.name)" }
            headerStack.addArrangedSubview(makeLabel(meta, .subheadline, color: .secondaryLabel))
            headerStack.addArrangedSubview(yearChips(record))
            if !record.fullView { headerStack.addArrangedSubview(notice("Bạn đang xem các môn mình dạy học sinh này.", tone: .info)) }
            if record.selectedYear?.locked == true { headerStack.addArrangedSubview(notice("Năm học đã khóa — chỉ xem điểm.", tone: .warning)) }
            if record.testTypes.isEmpty, !record.writableSubjectIds.isEmpty {
                headerStack.addArrangedSubview(notice("Chưa có Loại kiểm tra. Quản trị viên thêm tại Thiết lập loại kiểm tra.", tone: .warning))
            }
        } else if let errorMessage {
            headerStack.addArrangedSubview(notice("Chưa tải được học bạ: \(errorMessage)", tone: .danger))
        } else {
            headerStack.addArrangedSubview(makeLabel("Đang tải học bạ…", .headline))
        }
        tableView.reloadData()
        view.setNeedsLayout()
    }

    private func makeLabel(_ text: String, _ style: UIFont.TextStyle, color: UIColor = .label, weight: UIFont.Weight? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = weight.map { UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: $0)) }
            ?? .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func notice(_ text: String, tone: HomeroomTone) -> UIView {
        let label = makeLabel(text, .footnote, color: HomeroomPalette.colors(tone).text)
        let wrapper = UIStackView(arrangedSubviews: [label])
        wrapper.isLayoutMarginsRelativeArrangement = true
        wrapper.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        wrapper.backgroundColor = HomeroomPalette.colors(tone).background
        wrapper.layer.cornerRadius = 10
        wrapper.layer.cornerCurve = .continuous
        return wrapper
    }

    /// One chip per school year of the student (Khối x · Lớp y, ĐTB năm).
    private func yearChips(_ record: StudentRecord) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        for year in record.years {
            let selected = year.id == record.selectedYearId
            var configuration = selected ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
            configuration.baseBackgroundColor = selected ? HomeroomPalette.primaryBackground : nil
            configuration.baseForegroundColor = selected ? HomeroomPalette.primaryForeground : .label
            configuration.cornerStyle = .large
            configuration.title = "Khối \(year.gradeLevel == 0 ? "—" : String(year.gradeLevel)) · \(year.className.isEmpty ? "Lớp" : year.className)"
            let average = GradeMath.formatScore(record.yearSummaries[year.id]?.year)
            configuration.subtitle = "Năm học \(year.name) · ĐTB năm: \(average)"
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return updated
            }
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = "\(configuration.title ?? ""), năm học \(year.name), điểm trung bình năm \(average)"
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.record?.selectedYearId != year.id else { return }
                self.yearId = year.id
                self.reload()
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            scroll.frameLayoutGuide.heightAnchor.constraint(equalTo: row.heightAnchor),
        ])
        return scroll
    }

    // MARK: Table: one section per subject (HK I, HK II, Cả năm), then "ĐTB các môn"

    override func numberOfSections(in tableView: UITableView) -> Int {
        guard let record else { return 0 }
        return record.subjectIds.isEmpty ? 1 : record.subjectIds.count + 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let record else { return 0 }
        return record.subjectIds.isEmpty ? 1 : 3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let record, !record.subjectIds.isEmpty else { return nil }
        return section < record.subjectIds.count ? record.subjectName(record.subjectIds[section]) : "ĐTB các môn"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let record, !record.subjectIds.isEmpty, section == record.subjectIds.count else { return nil }
        return "ĐTB môn học kỳ = tổng (điểm × hệ số) / tổng hệ số · ĐTB cả năm = (HK I + 2 × HK II) / 3 · ĐTB học kỳ = trung bình các môn."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TeachingCell.reuseIdentifier, for: indexPath) as! TeachingCell
        guard let record else { return cell }
        guard !record.subjectIds.isEmpty else {
            cell.configure(title: "Chưa có môn học nào trong năm học này.", subtitle: "Môn học hiện theo Lịch dạy của lớp hoặc khi đã có điểm.", tappable: false)
            return cell
        }
        if indexPath.section == record.subjectIds.count {
            let values = [record.summary.semester1, record.summary.semester2, record.summary.year]
            let titles = ["Học kỳ I", "Học kỳ II", "Cả năm"]
            cell.configure(
                leading: GradeMath.formatScore(values[indexPath.row]),
                title: titles[indexPath.row],
                tappable: false,
                accessibilityLabel: "ĐTB các môn \(titles[indexPath.row]): \(GradeMath.formatScore(values[indexPath.row]))"
            )
            return cell
        }
        let subjectId = record.subjectIds[indexPath.section]
        let averages = record.subjectSummaries[subjectId]
        if indexPath.row == 2 {
            cell.configure(
                leading: GradeMath.formatScore(averages?.year),
                title: "Cả năm",
                tappable: false,
                accessibilityLabel: "\(record.subjectName(subjectId)), cả năm: \(GradeMath.formatScore(averages?.year))"
            )
            return cell
        }
        let semester = indexPath.row + 1
        let entries = record.entries(subjectId: subjectId, semester: semester)
        let editable = entries.contains(where: \.canEdit)
        let average = GradeMath.formatScore(semester == 1 ? averages?.semester1 : averages?.semester2)
        cell.configure(
            leading: average,
            title: GradebookLayout.semesterTitle(semester),
            subtitle: GradebookLayout.scoresText(entries),
            detail: editable ? "Bấm để sửa hoặc xóa điểm của bạn" : nil,
            tappable: editable,
            accessibilityLabel: "\(record.subjectName(subjectId)), \(GradebookLayout.semesterTitle(semester)), ĐTB \(average), điểm: \(GradebookLayout.scoresText(entries))"
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let record, indexPath.section < record.subjectIds.count, indexPath.row < 2 else { return }
        let entries = record.entries(subjectId: record.subjectIds[indexPath.section], semester: indexPath.row + 1).filter(\.canEdit)
        guard !entries.isEmpty else { return }
        if entries.count == 1 { return openForm(entry: entries[0]) }
        let sheet = UIAlertController(title: "Chọn điểm để sửa", message: nil, preferredStyle: .actionSheet)
        for entry in entries {
            sheet.addAction(UIAlertAction(title: "\(GradeMath.formatScore(entry.score)) · \(entry.testTypeName) (hệ số \(entry.coefficient))", style: .default) { [weak self] _ in
                self?.openForm(entry: entry)
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    @objc private func addScore() { openForm(entry: nil) }

    private func openForm(entry: GradeEntry?) {
        guard let record else { return }
        let form = ScoreFormViewController(repository: repository, record: record, entry: entry)
        form.onSaved = { [weak self] in self?.reload() }
        present(UINavigationController(rootViewController: form), animated: true)
    }
}

/// Thêm / sửa / xóa một điểm: Môn (khi có nhiều môn), Loại kiểm tra, Điểm số 0–10 (dấu phẩy hoặc chấm), Học kỳ.
@MainActor
final class ScoreFormViewController: UIViewController, UITextFieldDelegate {
    var onSaved: (() -> Void)?

    private let repository: TeachingRepository
    private let record: StudentRecord
    private let entry: GradeEntry?
    private var subjectId: String
    private var testTypeId: String
    private var saving = false
    private let subjectButton = UIButton(type: .system)
    private let testTypeButton = UIButton(type: .system)
    private let scoreField = UITextField()
    private let scoreError = UILabel()
    private let semesterControl = UISegmentedControl(items: ["Học kỳ I", "Học kỳ II"])
    private let errorLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private lazy var saveItem = UIBarButtonItem(title: "Lưu", style: .prominent, target: self, action: #selector(save))

    init(repository: TeachingRepository, record: StudentRecord, entry: GradeEntry?) {
        self.repository = repository
        self.record = record
        self.entry = entry
        subjectId = entry?.subjectId ?? record.writableSubjectIds.first ?? ""
        if let entry {
            // Removed test type: keep the stored one (the server only changes it when another type is picked).
            testTypeId = record.testTypes.contains { $0.id == entry.testTypeId } ? entry.testTypeId : ""
        } else {
            testTypeId = record.testTypes.first?.id ?? ""
        }
        super.init(nibName: nil, bundle: nil)
        title = entry == nil ? "Thêm điểm" : "Sửa điểm"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        isModalInPresentation = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = saveItem

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
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

        let year = record.selectedYear
        stack.addArrangedSubview(label("\(record.fullName)\(year.map { " · \($0.className) · \($0.name)" } ?? "")", .subheadline, color: .secondaryLabel))

        if let entry {
            let when = LessonLogViewController.timestamp(entry.createdAt)
            stack.addArrangedSubview(label("\(record.subjectName(entry.subjectId)) · nhập bởi \(entry.enteredByName.isEmpty ? "—" : entry.enteredByName) lúc \(when)", .footnote, color: .secondaryLabel))
        } else if record.writableSubjectIds.count > 1 {
            stack.addArrangedSubview(fieldLabel("Môn học"))
            configureMenuButton(subjectButton)
            stack.addArrangedSubview(subjectButton)
        } else {
            stack.addArrangedSubview(label("Môn: \(record.subjectName(subjectId))", .body))
        }

        stack.addArrangedSubview(fieldLabel("Loại kiểm tra"))
        configureMenuButton(testTypeButton)
        stack.addArrangedSubview(testTypeButton)

        stack.addArrangedSubview(fieldLabel("Điểm số (0 – 10)"))
        scoreField.borderStyle = .roundedRect
        scoreField.font = .preferredFont(forTextStyle: .body)
        scoreField.adjustsFontForContentSizeCategory = true
        scoreField.keyboardType = .decimalPad
        scoreField.placeholder = "Ví dụ 8,5"
        scoreField.accessibilityLabel = "Điểm số từ 0 đến 10"
        scoreField.text = entry.map { GradeMath.editText($0.score) }
        scoreField.delegate = self
        scoreField.addTarget(self, action: #selector(scoreChanged), for: .editingChanged)
        scoreField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(scoreField)
        scoreError.font = .preferredFont(forTextStyle: .footnote)
        scoreError.adjustsFontForContentSizeCategory = true
        scoreError.textColor = .systemRed
        scoreError.numberOfLines = 0
        scoreError.text = "Điểm từ 0 đến 10, tối đa 2 chữ số thập phân (ví dụ 8,5)."
        scoreError.isHidden = true
        stack.addArrangedSubview(scoreError)

        stack.addArrangedSubview(fieldLabel("Học kỳ"))
        let defaultSemester = TeachingSchedule.semesterForDate(TeachingSchedule.vietnamNow().date, semester2StartDate: year?.semester2StartDate ?? "")
        semesterControl.selectedSegmentIndex = (entry?.semester ?? defaultSemester) == 2 ? 1 : 0
        semesterControl.accessibilityLabel = "Học kỳ"
        semesterControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        stack.addArrangedSubview(semesterControl)

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        if entry != nil {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = "Xóa điểm"
            configuration.image = UIImage(systemName: "trash")
            configuration.imagePadding = 6
            configuration.baseForegroundColor = .systemRed
            configuration.baseBackgroundColor = .systemRed
            configuration.cornerStyle = .large
            deleteButton.configuration = configuration
            deleteButton.addTarget(self, action: #selector(confirmDelete), for: .touchUpInside)
            deleteButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            stack.setCustomSpacing(24, after: errorLabel)
            stack.addArrangedSubview(deleteButton)
        }
        refreshMenus()
        updateState()
    }

    private func label(_ text: String, _ style: UIFont.TextStyle, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func fieldLabel(_ text: String) -> UILabel {
        let label = label(text, .subheadline)
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        return label
    }

    private func configureMenuButton(_ button: UIButton) {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .medium
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.showsMenuAsPrimaryAction = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func refreshMenus() {
        subjectButton.menu = UIMenu(title: "Môn học", children: record.writableSubjectIds.map { id in
            UIAction(title: record.subjectName(id), state: id == subjectId ? .on : .off) { [weak self] _ in
                self?.subjectId = id
                self?.refreshMenus()
            }
        })
        subjectButton.configuration?.title = record.subjectName(subjectId)
        subjectButton.accessibilityLabel = "Môn học, \(record.subjectName(subjectId))"

        var actions: [UIAction] = []
        if let entry, !record.testTypes.contains(where: { $0.id == entry.testTypeId }) {
            actions.append(UIAction(title: "\(entry.testTypeName) (hệ số \(entry.coefficient))", state: testTypeId.isEmpty ? .on : .off) { [weak self] _ in
                self?.testTypeId = ""
                self?.refreshMenus()
            })
        }
        actions += record.testTypes.map { type in
            UIAction(title: "\(type.name) (hệ số \(type.coefficient))", state: type.id == testTypeId ? .on : .off) { [weak self] _ in
                self?.testTypeId = type.id
                self?.refreshMenus()
            }
        }
        testTypeButton.menu = UIMenu(title: "Loại kiểm tra", children: actions)
        let typeTitle: String
        if let type = record.testTypes.first(where: { $0.id == testTypeId }) {
            typeTitle = "\(type.name) (hệ số \(type.coefficient))"
        } else if let entry {
            typeTitle = "\(entry.testTypeName) (hệ số \(entry.coefficient))"
        } else {
            typeTitle = "Chọn loại kiểm tra"
        }
        testTypeButton.configuration?.title = typeTitle
        testTypeButton.accessibilityLabel = "Loại kiểm tra, \(typeTitle)"
        updateState()
    }

    @objc private func scoreChanged() { updateState() }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let next = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        return next.count <= 6
    }

    private var scoreText: String { scoreField.text ?? "" }

    private func updateState() {
        let typed = !scoreText.trimmingCharacters(in: .whitespaces).isEmpty
        let valid = GradeMath.parseScore(scoreText) != nil
        scoreError.isHidden = !typed || valid
        let typeChosen = !testTypeId.isEmpty || entry != nil
        saveItem.isEnabled = !saving && valid && !subjectId.isEmpty && typeChosen
        saveItem.title = saving ? "Đang lưu…" : "Lưu"
        deleteButton.isEnabled = !saving
    }

    private func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
        if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func save() {
        guard !saving else { return }
        let semester = semesterControl.selectedSegmentIndex == 1 ? 2 : 1
        let args: [String: Any]
        do {
            if let entry {
                args = try TeachingPayload.updateScore(entry: entry, semester: semester, testTypeId: testTypeId, scoreText: scoreText)
            } else {
                args = try TeachingPayload.addScore(record: record, subjectId: subjectId, semester: semester, testTypeId: testTypeId, scoreText: scoreText)
            }
        } catch {
            showError(TeachingText.message(error))
            return
        }
        run { [repository, entry] in
            if entry != nil { try await repository.updateScore(args) } else { try await repository.addScore(args) }
        }
    }

    @objc private func confirmDelete() {
        guard let entry else { return }
        let alert = UIAlertController(
            title: "Xóa điểm này?",
            message: "\(record.subjectName(entry.subjectId)) · \(entry.testTypeName): \(GradeMath.formatScore(entry.score)). ĐTB sẽ được tính lại.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa điểm", style: .destructive) { [weak self] _ in
            guard let self else { return }
            run { [repository] in try await repository.removeScore(id: entry.id) }
        })
        present(alert, animated: true)
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        saving = true
        showError(nil)
        updateState()
        Task { [weak self] in
            do {
                try await operation()
                guard let self else { return }
                saving = false
                onSaved?()
                dismiss(animated: true)
            } catch {
                guard let self else { return }
                saving = false
                showError(TeachingText.message(error))
                updateState()
            }
        }
    }
}
