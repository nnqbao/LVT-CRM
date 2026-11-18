import UIKit

/// Văn thư edits one duty of the shared sheet. Saving sends the week back for BGH approval.
@MainActor
final class DutyEditViewController: UIViewController {
    private let repository: DutiesRepository
    private let onSaved: () -> Void
    private var draft: DutyDraft
    private var options: DutyFormOptions?
    private var saving = false

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let titleField = UITextField()
    private let contentField = UITextView()
    private let allDaySwitch = UISwitch()
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private let endRow = UIStackView()
    private let locationField = UITextField()
    private let departmentsButton = UIButton(configuration: .bordered())
    private let usersButton = UIButton(configuration: .bordered())
    private let otherField = UITextField()
    private let errorLabel = UILabel()
    private let saveButton = UIButton(configuration: .filled())
    private let spinner = UIActivityIndicatorView(style: .large)

    init(repository: DutiesRepository, event: SharedDutyEvent, onSaved: @escaping () -> Void) {
        self.repository = repository
        self.onSaved = onSaved
        self.draft = DutyEditRules.draft(from: event)
        super.init(nibName: nil, bundle: nil)
        title = "Sửa công tác"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        buildForm()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        stack.isHidden = true
        spinner.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            do {
                options = try await repository.formOptions()
                stack.isHidden = false
                render()
            } catch {
                errorLabel.text = (error as? LocalizedError)?.errorDescription ?? "Không tải được danh sách phòng ban, người dùng."
                errorLabel.isHidden = false
                stack.isHidden = false
                saveButton.isEnabled = false
            }
            spinner.stopAnimating()
        }
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func buildForm() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        styleField(titleField, placeholder: "Tên công tác")
        titleField.text = draft.title
        contentField.text = draft.content
        contentField.font = .preferredFont(forTextStyle: .body)
        contentField.adjustsFontForContentSizeCategory = true
        contentField.layer.cornerRadius = 8
        contentField.layer.borderWidth = 1
        contentField.layer.borderColor = UIColor.separator.cgColor
        contentField.isScrollEnabled = false
        contentField.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true

        allDaySwitch.isOn = draft.allDay
        allDaySwitch.addAction(UIAction { [weak self] _ in self?.render() }, for: .valueChanged)
        let allDayRow = UIStackView(arrangedSubviews: [label("Cả ngày"), UIView(), allDaySwitch])
        allDayRow.alignment = .center

        for picker in [startPicker, endPicker] {
            picker.preferredDatePickerStyle = .compact
            picker.locale = Locale(identifier: "vi_VN")
            picker.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        }
        startPicker.date = Self.date(draft.startDate, draft.startTime)
        endPicker.date = Self.date(draft.endDate, draft.endTime)
        let startRow = UIStackView(arrangedSubviews: [label("Từ"), UIView(), startPicker])
        startRow.alignment = .center
        endRow.addArrangedSubview(label("Đến"))
        endRow.addArrangedSubview(UIView())
        endRow.addArrangedSubview(endPicker)
        endRow.alignment = .center

        styleField(locationField, placeholder: "Địa điểm")
        locationField.text = draft.locationText
        styleField(otherField, placeholder: "Thành phần khác (đoàn công tác, khách mời…)")
        otherField.text = draft.otherParticipants

        departmentsButton.configuration?.titleAlignment = .leading
        departmentsButton.contentHorizontalAlignment = .leading
        departmentsButton.addAction(UIAction { [weak self] _ in self?.pick(departments: true) }, for: .touchUpInside)
        usersButton.contentHorizontalAlignment = .leading
        usersButton.addAction(UIAction { [weak self] _ in self?.pick(departments: false) }, for: .touchUpInside)

        let note = label("Lưu xong, thay đổi chờ Ban Giám hiệu duyệt. Giáo viên vẫn thấy bản đã duyệt trước đó.")
        note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.isHidden = true

        saveButton.configuration?.title = "Lưu thay đổi"
        saveButton.configuration?.cornerStyle = .large
        saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        saveButton.addAction(UIAction { [weak self] _ in self?.confirmSave() }, for: .touchUpInside)

        [
            label("Tên công tác"), titleField,
            label("Nội dung"), contentField,
            allDayRow, startRow, endRow,
            label("Địa điểm"), locationField,
            label("Thành phần"), departmentsButton, usersButton, otherField,
            note, errorLabel, saveButton,
        ].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(18, after: endRow)
        stack.setCustomSpacing(18, after: locationField)
        stack.setCustomSpacing(18, after: otherField)
    }

    private func render() {
        endRow.isHidden = allDaySwitch.isOn
        startPicker.datePickerMode = allDaySwitch.isOn ? .date : .dateAndTime
        guard let options else { return }
        departmentsButton.isHidden = !options.isOps
        departmentsButton.configuration?.title = DutyEditRules.selectionLabel("Phòng ban", ids: draft.departmentIds, options: options.departments)
        usersButton.configuration?.title = DutyEditRules.selectionLabel("Cá nhân", ids: draft.participantUserIds, options: options.users)
    }

    private func pick(departments: Bool) {
        guard let options else { return }
        let picker = DutyMultiSelectViewController(
            title: departments ? "Chọn phòng ban" : "Chọn cá nhân",
            options: departments ? options.departments : options.users,
            selected: Set(departments ? draft.departmentIds : draft.participantUserIds)
        ) { [weak self] ids in
            guard let self else { return }
            if departments { draft.departmentIds = ids } else { draft.participantUserIds = ids }
            render()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func collect() {
        draft.title = titleField.text ?? ""
        draft.content = contentField.text ?? ""
        draft.locationText = locationField.text ?? ""
        draft.otherParticipants = otherField.text ?? ""
        draft.allDay = allDaySwitch.isOn
        let start = Self.parts(startPicker.date)
        let end = Self.parts(endPicker.date)
        draft.startDate = start.date
        draft.startTime = start.time
        draft.endDate = end.date
        draft.endTime = end.time
    }

    private func confirmSave() {
        guard !saving else { return }
        collect()
        if let message = DutyEditRules.error(draft) {
            errorLabel.text = message
            errorLabel.isHidden = false
            return
        }
        errorLabel.isHidden = true
        let alert = UIAlertController(title: "Lưu thay đổi?", message: "Lịch tuần sẽ cần Ban Giám hiệu duyệt lại.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in self?.save() })
        present(alert, animated: true)
    }

    private func save() {
        saving = true
        saveButton.isEnabled = false
        saveButton.configuration?.showsActivityIndicator = true
        let value = DutyEditRules.trimmed(draft)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.updateDuty(value)
                onSaved()
                navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                errorLabel.text = (error as? LocalizedError)?.errorDescription ?? "Không lưu được. Hãy thử lại."
                errorLabel.isHidden = false
            }
            saving = false
            saveButton.isEnabled = true
            saveButton.configuration?.showsActivityIndicator = false
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        return calendar
    }

    private static func date(_ iso: String, _ time: String) -> Date {
        let day = iso.split(separator: "-").compactMap { Int($0) }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(
            year: day.count == 3 ? day[0] : nil,
            month: day.count == 3 ? day[1] : nil,
            day: day.count == 3 ? day[2] : nil,
            hour: clock.first ?? 7,
            minute: clock.count > 1 ? clock[1] : 0
        )
        return calendar.date(from: components) ?? Date()
    }

    private static func parts(_ date: Date) -> (date: String, time: String) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (
            String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
            String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        )
    }
}

/// Searchable checklist for departments or people.
@MainActor
final class DutyMultiSelectViewController: UITableViewController, UISearchResultsUpdating {
    private let options: [DutyFormOption]
    private var selected: Set<String>
    private var visible: [DutyFormOption]
    private let onDone: ([String]) -> Void

    init(title: String, options: [DutyFormOption], selected: Set<String>, onDone: @escaping ([String]) -> Void) {
        self.options = options
        self.selected = selected
        self.visible = options
        self.onDone = onDone
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            onDone(options.map(\.id).filter { self.selected.contains($0) })
            dismiss(animated: true)
        })
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Tìm…"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        visible = query.isEmpty ? options : options.filter {
            $0.label.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visible.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = visible[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = option.label
        content.secondaryText = option.detail.isEmpty ? nil : option.detail
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = selected.contains(option.id) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = visible[indexPath.row].id
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
