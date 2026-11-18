import UIKit

/// "Việc của tôi" list (web PersonalTodosView): open first, then recently completed. Complete toggle, edit,
/// delete with confirmation. Owner-only on the server; available to every active account.
@MainActor
final class PersonalTodosViewController: UITableViewController {
    private enum Section {
        case intro
        case feedback(String, HomeroomTone)
        case loading
        case error(String)
        case open([PersonalTodo])
        case completed([PersonalTodo])
    }

    private let repository: PersonalTodoRepository
    private var list: PersonalTodoList?
    private var loading = false
    private var loadError: String?
    private var feedback: (String, HomeroomTone)?
    private var busyId: String?
    private var pendingFocusId: String?
    private var sections: [Section] = []
    private var loadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var generation = 0
    var trailingAccessoryBarButtonItems: [UIBarButtonItem] = [] {
        didSet { if isViewLoaded { applyBarButtonItems() } }
    }
    /// Called whenever this controller's bar items change (WorkHub mirrors them on its own navigation item).
    var onBarItemsChange: (() -> Void)?

    init(repository: PersonalTodoRepository) {
        self.repository = repository
        super.init(style: .insetGrouped)
        title = "Việc của tôi"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        loadTask?.cancel()
        actionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.register(HomeroomBannerCell.self, forCellReuseIdentifier: HomeroomBannerCell.reuseIdentifier)
        tableView.register(PersonalTodoCell.self, forCellReuseIdentifier: PersonalTodoCell.reuseIdentifier)
        refreshControl = UIRefreshControl()
        refreshControl?.accessibilityLabel = "Tải lại danh sách việc"
        refreshControl?.addAction(UIAction { [weak self] _ in self?.load() }, for: .valueChanged)
        applyBarButtonItems()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    /// Opens a todo from a reminder (push `todo` / bell `todo_reminder`): scroll to it once the list is loaded.
    func focus(todoId: String) {
        loadViewIfNeeded()
        pendingFocusId = todoId
        load()
    }

    private func applyBarButtonItems() {
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.openForm(nil) })
        add.accessibilityLabel = "Thêm việc"
        navigationItem.rightBarButtonItems = trailingAccessoryBarButtonItems + [add]
        onBarItemsChange?()
    }

    // MARK: - Data

    private func load() {
        loadTask?.cancel()
        generation += 1
        let version = generation
        loading = true
        loadError = nil
        if list == nil { render() }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await repository.listMine()
                guard !Task.isCancelled, generation == version else { return }
                list = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == version else { return }
                loadError = error.localizedDescription
            }
            loading = false
            refreshControl?.endRefreshing()
            render()
            processPendingFocus()
        }
    }

    private func run(_ todo: PersonalTodo, success: String?, operation: @escaping () async throws -> Void) {
        guard busyId == nil else { return }
        busyId = todo.id
        feedback = nil
        render()
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                if let success { feedback = (success, .success) }
            } catch is CancellationError {
                busyId = nil
                return
            } catch {
                feedback = (error.localizedDescription, .danger)
            }
            busyId = nil
            if let message = feedback?.0 { UIAccessibility.post(notification: .announcement, argument: message) }
            load()
            render()
        }
    }

    private func toggle(_ todo: PersonalTodo) {
        let done = !todo.isCompleted
        run(todo, success: done ? "Đã hoàn thành “\(todo.title)”." : "Đã mở lại “\(todo.title)”.") { [repository] in
            try await repository.setCompleted(id: todo.id, done: done)
        }
    }

    private func confirmDelete(_ todo: PersonalTodo) {
        let alert = UIAlertController(title: "Xóa việc", message: PersonalTodos.deletePrompt(todo), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.run(todo, success: "Đã xóa việc.") { [repository = self?.repository] in
                try await repository?.remove(id: todo.id)
            }
        })
        present(alert, animated: true)
    }

    private func openForm(_ todo: PersonalTodo?) {
        let form = PersonalTodoFormViewController(repository: repository, todo: todo) { [weak self] message in
            self?.feedback = (message, .success)
            self?.load()
            self?.render()
        }
        let navigation = UINavigationController(rootViewController: form)
        present(navigation, animated: true)
    }

    private func processPendingFocus() {
        guard let id = pendingFocusId, let list else { return }
        pendingFocusId = nil
        guard list.contains(id) else {
            feedback = ("Việc này không còn tồn tại hoặc đã bị xóa.", .warning)
            render()
            return
        }
        for (sectionIndex, section) in sections.enumerated() {
            let items: [PersonalTodo]
            switch section {
            case let .open(rows), let .completed(rows): items = rows
            default: continue
            }
            if let row = items.firstIndex(where: { $0.id == id }) {
                let indexPath = IndexPath(row: row, section: sectionIndex)
                tableView.scrollToRow(at: indexPath, at: .middle, animated: !UIAccessibility.isReduceMotionEnabled)
                UIAccessibility.post(notification: .layoutChanged, argument: tableView.cellForRow(at: indexPath))
                return
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        var result: [Section] = [.intro]
        if let feedback { result.append(.feedback(feedback.0, feedback.1)) }
        if let list {
            if let loadError { result.append(.feedback("Chưa làm mới được: \(loadError)", .warning)) }
            result.append(.open(list.open))
            if !list.completed.isEmpty { result.append(.completed(list.completed)) }
        } else if let loadError {
            result.append(.error(loadError))
        } else if loading {
            result.append(.loading)
        }
        sections = result
        tableView.reloadData()
    }

    private func todo(at indexPath: IndexPath) -> PersonalTodo? {
        switch sections[indexPath.section] {
        case let .open(rows), let .completed(rows): return rows.indices.contains(indexPath.row) ? rows[indexPath.row] : nil
        default: return nil
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case let .open(rows): return max(rows.count, 1)
        case let .completed(rows): return rows.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case let .open(rows): return "Cần làm (\(rows.count))"
        case let .completed(rows): return "Đã hoàn thành gần đây (\(rows.count))"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .intro:
            return textCell(PersonalTodos.intro, style: .subheadline, color: .secondaryLabel)
        case let .feedback(message, tone):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
            cell.configure(title: message, message: nil, tone: tone, symbol: tone == .success ? "checkmark.circle" : "exclamationmark.triangle")
            return cell
        case .loading:
            return textCell("Đang tải danh sách việc…", style: .body, color: .secondaryLabel)
        case let .error(message):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
            cell.configure(title: "Không tải được danh sách việc", message: "\(message)\nKéo xuống để thử lại.", tone: .danger, symbol: "exclamationmark.triangle")
            return cell
        case let .open(rows) where rows.isEmpty:
            return textCell("Chưa có việc cần làm. Nhấn + để thêm việc.", style: .body, color: .secondaryLabel)
        case .open, .completed:
            guard let todo = todo(at: indexPath) else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: PersonalTodoCell.reuseIdentifier, for: indexPath) as! PersonalTodoCell
            let busy = busyId == todo.id
            cell.configure(todo, now: PersonalTodos.nowMs(), busy: busy || busyId != nil)
            cell.onToggle = { [weak self] in self?.toggle(todo) }
            cell.accessibilityCustomActions = actions(for: todo)
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .error = sections[indexPath.section] { load(); return }
        guard let todo = todo(at: indexPath), !todo.isCompleted, busyId == nil else { return }
        openForm(todo)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let todo = todo(at: indexPath), busyId == nil else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Xóa") { [weak self] _, _, done in
            self?.confirmDelete(todo)
            done(true)
        }
        var actions = [delete]
        if !todo.isCompleted {
            let edit = UIContextualAction(style: .normal, title: "Sửa") { [weak self] _, _, done in
                self?.openForm(todo)
                done(true)
            }
            edit.backgroundColor = HomeroomPalette.colors(.info).text
            actions.append(edit)
        }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func actions(for todo: PersonalTodo) -> [UIAccessibilityCustomAction] {
        var result = [UIAccessibilityCustomAction(name: todo.isCompleted ? "Mở lại" : "Hoàn thành") { [weak self] _ in
            self?.toggle(todo)
            return true
        }]
        if !todo.isCompleted {
            result.append(UIAccessibilityCustomAction(name: "Sửa") { [weak self] _ in
                self?.openForm(todo)
                return true
            })
        }
        result.append(UIAccessibilityCustomAction(name: "Xóa") { [weak self] _ in
            self?.confirmDelete(todo)
            return true
        })
        return result
    }

    private func textCell(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "text") ?? UITableViewCell(style: .default, reuseIdentifier: "text")
        var content = cell.defaultContentConfiguration()
        content.text = text
        content.textProperties.font = .preferredFont(forTextStyle: style)
        content.textProperties.color = color
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}

/// Checkbox (complete toggle), title, optional note, status pill and time lines.
final class PersonalTodoCell: UITableViewCell {
    static let reuseIdentifier = "personal-todo"
    var onToggle: (() -> Void)?
    private let check = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let metaLabel = UILabel()
    private let chips = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        check.addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .touchUpInside)
        check.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        check.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        check.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 3
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 0
        chips.axis = .horizontal
        let chipRow = UIStackView(arrangedSubviews: [chips, UIView()])
        let texts = UIStackView(arrangedSubviews: [titleLabel, noteLabel, chipRow, metaLabel])
        texts.axis = .vertical
        texts.spacing = 4
        let row = UIStackView(arrangedSubviews: [check, texts])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ todo: PersonalTodo, now: Int64, busy: Bool) {
        let done = todo.isCompleted
        let success = HomeroomPalette.colors(.success).text
        check.setImage(UIImage(systemName: done ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title2)), for: .normal)
        check.tintColor = done ? success : .secondaryLabel
        check.isEnabled = !busy
        check.accessibilityLabel = "Hoàn thành: \(todo.title)"
        check.accessibilityValue = done ? "Đã hoàn thành" : "Chưa hoàn thành"
        check.accessibilityTraits = done ? [.button, .selected] : .button
        titleLabel.attributedText = NSAttributedString(string: todo.title, attributes: done ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue] : [:])
        titleLabel.textColor = done ? .secondaryLabel : .label
        noteLabel.text = todo.note
        noteLabel.isHidden = todo.note.isEmpty
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let status = PersonalTodos.status(todo, now: now) {
            chips.addArrangedSubview(HomeroomChipLabel(HomeroomChip(text: status, tone: done ? .success : .danger)))
        }
        chips.superview?.isHidden = chips.arrangedSubviews.isEmpty
        metaLabel.text = PersonalTodos.metaLines(todo).joined(separator: "\n")
        accessoryType = done ? .none : .disclosureIndicator
        selectionStyle = done ? .none : .default
        accessibilityElements = [check, titleLabel, noteLabel, chips, metaLabel].filter { !$0.isHidden }
    }
}

/// Create / edit form: Tên việc, Ghi chú, Hạn chót, Nhắc lúc (date pickers). Labels above inputs, errors under
/// each field, server error at the top, one primary action.
@MainActor
final class PersonalTodoFormViewController: UIViewController, UITextViewDelegate {
    private let repository: PersonalTodoRepository
    private let todo: PersonalTodo?
    private let onDone: (String) -> Void
    private var form: PersonalTodoForm
    private var saving = false
    private var task: Task<Void, Never>?
    private let scrollView = UIScrollView()
    private let serverError = UILabel()
    private let titleField = UITextField()
    private let noteView = UITextView()
    private let dueSwitch = UISwitch()
    private let duePicker = UIDatePicker()
    private let remindSwitch = UISwitch()
    private let remindPicker = UIDatePicker()
    private var errorLabels: [String: UILabel] = [:]
    private lazy var saveItem = UIBarButtonItem(title: todo == nil ? "Thêm việc" : "Lưu", style: .prominent, target: self, action: #selector(save))

    init(repository: PersonalTodoRepository, todo: PersonalTodo?, onDone: @escaping (String) -> Void) {
        self.repository = repository
        self.todo = todo
        self.onDone = onDone
        form = todo.map(PersonalTodoForm.init) ?? PersonalTodoForm()
        super.init(nibName: nil, bundle: nil)
        title = todo == nil ? "Thêm việc" : "Sửa việc"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = saveItem

        serverError.font = .preferredFont(forTextStyle: .subheadline)
        serverError.adjustsFontForContentSizeCategory = true
        serverError.textColor = HomeroomPalette.colors(.danger).text
        serverError.numberOfLines = 0
        serverError.isHidden = true

        titleField.text = form.title
        titleField.font = .preferredFont(forTextStyle: .body)
        titleField.adjustsFontForContentSizeCategory = true
        titleField.borderStyle = .roundedRect
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .next
        titleField.accessibilityLabel = "Tên việc, bắt buộc"
        titleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        titleField.addAction(UIAction { [weak self] _ in
            self?.form.title = self?.titleField.text ?? ""
            self?.setError("title", nil)
        }, for: .editingChanged)

        noteView.text = form.note
        noteView.font = .preferredFont(forTextStyle: .body)
        noteView.adjustsFontForContentSizeCategory = true
        noteView.isScrollEnabled = false
        noteView.backgroundColor = .secondarySystemGroupedBackground
        noteView.layer.cornerRadius = 8
        noteView.layer.borderWidth = 1
        noteView.layer.borderColor = UIColor.separator.cgColor
        noteView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        noteView.accessibilityLabel = "Ghi chú"
        noteView.delegate = self
        noteView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        configurePicker(duePicker, switchControl: dueSwitch, value: form.dueAt, label: "Hạn chót")
        configurePicker(remindPicker, switchControl: remindSwitch, value: form.remindAt, label: "Nhắc lúc")
        dueSwitch.addAction(UIAction { [weak self] _ in self?.dueToggled() }, for: .valueChanged)
        remindSwitch.addAction(UIAction { [weak self] _ in self?.remindToggled() }, for: .valueChanged)
        duePicker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            form.dueAt = PersonalTodos.minuteMs(duePicker.date)
            setError("due", nil)
        }, for: .valueChanged)
        remindPicker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            form.remindAt = PersonalTodos.minuteMs(remindPicker.date)
            setError("remind", nil)
        }, for: .valueChanged)

        let help = UILabel()
        help.text = "Gửi thông báo tới bạn vào giờ này."
        help.font = .preferredFont(forTextStyle: .footnote)
        help.adjustsFontForContentSizeCategory = true
        help.textColor = .secondaryLabel
        help.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            serverError,
            field("Tên việc *", titleField, key: "title"),
            field("Ghi chú", noteView, key: "note"),
            field("Hạn chót", toggleRow("Có hạn chót", dueSwitch, duePicker), key: "due"),
            field("Nhắc lúc", toggleRow("Nhắc tôi", remindSwitch, remindPicker), key: "remind", help: help),
        ])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(stack)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        isModalInPresentation = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if todo == nil { titleField.becomeFirstResponder() }
    }

    func textViewDidChange(_ textView: UITextView) {
        form.note = textView.text ?? ""
        setError("note", nil)
    }

    private func configurePicker(_ picker: UIDatePicker, switchControl: UISwitch, value: Int64?, label: String) {
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.calendar = Calendar(identifier: .gregorian)
        picker.timeZone = VietnamDate.timeZone
        picker.locale = Locale(identifier: "vi_VN")
        picker.minuteInterval = 1
        picker.accessibilityLabel = label
        picker.date = value.map(PersonalTodos.date) ?? defaultDate()
        picker.isHidden = value == nil
        switchControl.isOn = value != nil
        switchControl.accessibilityLabel = label
    }

    /// Next full hour, a sensible default for a new due/reminder time.
    private func defaultDate() -> Date {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = VietnamDate.timeZone
        let hour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
        return hour
    }

    private func dueToggled() {
        duePicker.isHidden = !dueSwitch.isOn
        form.dueAt = dueSwitch.isOn ? PersonalTodos.minuteMs(duePicker.date) : nil
        setError("due", nil)
    }

    private func remindToggled() {
        if remindSwitch.isOn, remindPicker.date <= Date() { remindPicker.date = defaultDate() }
        remindPicker.isHidden = !remindSwitch.isOn
        if remindSwitch.isOn {
            // Keep an unchanged (already fired) reminder exactly as stored; otherwise use the picker value.
            form.remindAt = todo?.remindAt.flatMap { PersonalTodos.date($0) == remindPicker.date ? $0 : nil } ?? PersonalTodos.minuteMs(remindPicker.date)
        } else {
            form.remindAt = nil
        }
        setError("remind", nil)
    }

    private func field(_ title: String, _ control: UIView, key: String, help: UILabel? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.isAccessibilityElement = false
        let error = UILabel()
        error.font = .preferredFont(forTextStyle: .footnote)
        error.adjustsFontForContentSizeCategory = true
        error.textColor = HomeroomPalette.colors(.danger).text
        error.numberOfLines = 0
        error.isHidden = true
        errorLabels[key] = error
        let stack = UIStackView(arrangedSubviews: [label, control, error] + (help.map { [$0] } ?? []))
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func toggleRow(_ title: String, _ switchControl: UISwitch, _ picker: UIDatePicker) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [label, switchControl])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [row, picker])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        return stack
    }

    private func setError(_ key: String, _ message: String?) {
        guard let label = errorLabels[key] else { return }
        label.text = message
        label.isHidden = message == nil
    }

    @objc private func cancel() {
        guard !saving else { return }
        task?.cancel()
        dismiss(animated: true)
    }

    @objc private func save() {
        guard !saving else { return }
        view.endEditing(true)
        form.title = titleField.text ?? ""
        form.note = noteView.text ?? ""
        let validation = PersonalTodos.validate(form, now: PersonalTodos.nowMs(), previousRemindAt: todo?.remindAt)
        for key in ["title", "note", "due", "remind"] { setError(key, validation.errors[key]) }
        guard validation.ok else {
            let first = ["title", "note", "due", "remind"].compactMap { validation.errors[$0] }.first
            UIAccessibility.post(notification: .announcement, argument: first)
            return
        }
        setSaving(true)
        serverError.isHidden = true
        let form = self.form
        let editing = todo
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let editing { try await repository.update(id: editing.id, form: form) }
                else { try await repository.create(form) }
                setSaving(false)
                dismiss(animated: true)
                onDone(editing == nil ? "Đã thêm việc." : "Đã lưu việc.")
            } catch is CancellationError {
                setSaving(false)
            } catch {
                setSaving(false)
                serverError.text = error.localizedDescription
                serverError.isHidden = false
                scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
                UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
            }
        }
    }

    private func setSaving(_ value: Bool) {
        saving = value
        saveItem.isEnabled = !value
        saveItem.title = value ? "Đang lưu…" : (todo == nil ? "Thêm việc" : "Lưu")
        navigationItem.leftBarButtonItem?.isEnabled = !value
        ([titleField, dueSwitch, remindSwitch, duePicker, remindPicker] as [UIControl]).forEach { $0.isEnabled = !value }
        noteView.isEditable = !value
    }
}
