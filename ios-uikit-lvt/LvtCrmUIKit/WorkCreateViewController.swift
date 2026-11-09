import UIKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class WorkCreateViewController: UIViewController, UITextViewDelegate, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    private let viewModel: WorkViewModel
    private let editingWork: WorkApprovalItem?
    private let onCreated: () -> Void

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let titleField = UITextField()
    private let addRow = UIStackView()
    private let assignmentsStack = UIStackView()
    private let fileLabel = UILabel()
    private let typeButton = UIButton(type: .system)
    private let approverBlock = UIStackView()
    private let approverTitle = UILabel()
    private let approverNote = UILabel()
    private let approverButton = UIButton(type: .system)
    private let reapprovalLabel = UILabel()
    private let errorLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var options: WorkFormOptions?
    private var assignments: [WorkCreateAssignment] = []
    private var fileData: Data?
    private var fileName = ""
    private var fileMime = ""
    private var documentTypeId = ""
    private var keptFileName = ""
    private var approverIds: [String] = []
    private var isBusy = false

    private static let maxUploadFileSize = 20 * 1024 * 1024
    private static let allowedUploadExtensions: Set<String> = ["pdf", "docx", "xlsx", "xls", "png", "jpg", "jpeg"]

    init(viewModel: WorkViewModel, editingWork: WorkApprovalItem? = nil, onCreated: @escaping () -> Void) {
        self.viewModel = viewModel
        self.editingWork = editingWork
        self.onCreated = onCreated
        super.init(nibName: nil, bundle: nil)
        title = editingWork == nil ? "Tạo công việc" : "Sửa công việc"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        if let editingWork {
            titleField.text = WorkHelpers.listTitle(editingWork)
            assignments = editingWork.editAssignments()
            documentTypeId = editingWork.documentTypeId
            if editingWork.privateFile {
                keptFileName = editingWork.fileName
            }
            approverIds = editingWork.approvers.map(\.id)
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Hủy sửa",
                style: .plain,
                target: self,
                action: #selector(confirmCancel)
            )
        }
        configureViews()
        configureLayout()
        refreshApprovers()
        rebuildAssignments()
        refreshFileLabel()
        Task { await loadOptions() }
    }

    private func configureViews() {
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleField.placeholder = "Tên công việc"
        titleField.borderStyle = .roundedRect
        titleField.font = .preferredFont(forTextStyle: .body)
        titleField.adjustsFontForContentSizeCategory = true
        titleField.accessibilityLabel = "Tên công việc"

        addRow.axis = .horizontal
        addRow.spacing = 8
        addRow.distribution = .fillEqually
        let addPerson = UIButton(type: .system)
        addPerson.setTitle("＋ Cá nhân", for: .normal)
        addPerson.addTarget(self, action: #selector(addIndividual), for: .touchUpInside)
        addRow.addArrangedSubview(addPerson)

        assignmentsStack.axis = .vertical
        assignmentsStack.spacing = 12

        fileLabel.font = .preferredFont(forTextStyle: .body)
        fileLabel.adjustsFontForContentSizeCategory = true
        fileLabel.numberOfLines = 0
        fileLabel.textColor = .secondaryLabel
        fileLabel.text = "Tệp đính kèm (không bắt buộc)"

        typeButton.setTitle("Chọn loại văn bản", for: .normal)
        typeButton.contentHorizontalAlignment = .leading
        typeButton.addTarget(self, action: #selector(pickDocumentType), for: .touchUpInside)
        typeButton.isHidden = true
        typeButton.accessibilityLabel = "Loại văn bản"

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        approverBlock.axis = .vertical
        approverBlock.spacing = 6
        approverBlock.isLayoutMarginsRelativeArrangement = true
        approverBlock.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        approverBlock.backgroundColor = .secondarySystemGroupedBackground
        approverBlock.layer.cornerRadius = 12
        approverBlock.isHidden = true
        approverTitle.font = .preferredFont(forTextStyle: .headline)
        approverTitle.adjustsFontForContentSizeCategory = true
        approverTitle.numberOfLines = 0
        approverNote.font = .preferredFont(forTextStyle: .footnote)
        approverNote.adjustsFontForContentSizeCategory = true
        approverNote.textColor = .secondaryLabel
        approverNote.numberOfLines = 0
        approverNote.text = WorkApprovalRules.approvalNote
        approverButton.contentHorizontalAlignment = .leading
        approverButton.titleLabel?.numberOfLines = 0
        approverButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        approverButton.titleLabel?.adjustsFontForContentSizeCategory = true
        approverButton.addTarget(self, action: #selector(pickApprovers), for: .touchUpInside)
        reapprovalLabel.font = .preferredFont(forTextStyle: .footnote)
        reapprovalLabel.adjustsFontForContentSizeCategory = true
        reapprovalLabel.textColor = .systemOrange
        reapprovalLabel.numberOfLines = 0
        reapprovalLabel.text = WorkApprovalRules.reapprovalWarning
        reapprovalLabel.isHidden = !WorkApprovalRules.editNeedsReapproval(editingWork)
        approverBlock.addArrangedSubview(reapprovalLabel)
        approverBlock.addArrangedSubview(approverTitle)
        approverBlock.addArrangedSubview(approverNote)
        approverBlock.addArrangedSubview(approverButton)

        submitButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        submitButton.addTarget(self, action: #selector(submit), for: .touchUpInside)

        spinner.hidesWhenStopped = true
    }

    private func configureLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        let photoButton = outlineButton("Chọn từ Thư viện ảnh", action: #selector(pickPhoto))
        let fileButton = outlineButton("Chọn từ Tệp (PDF, Word, Excel)", action: #selector(pickFile))
        let clearFile = UIButton(type: .system)
        clearFile.setTitle("Gỡ tệp", for: .normal)
        clearFile.addTarget(self, action: #selector(removeFile), for: .touchUpInside)

        [
            titleField,
            addRow,
            assignmentsStack,
            approverBlock,
            fileLabel,
            photoButton,
            fileButton,
            clearFile,
            typeButton,
            errorLabel,
            submitButton,
            spinner,
        ].forEach { stackView.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func outlineButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func loadOptions() async {
        do {
            let loaded = try await viewModel.loadFormOptions()
            options = loaded
            if editingWork?.privateFile == true && documentTypeId.isEmpty,
               let fallback = loaded.documentTypes.first(where: { $0.code == "BIEN_BAN" }) {
                documentTypeId = fallback.id
            }
            refreshTypeButton()
            if loaded.canAssignDepartments, addRow.arrangedSubviews.count == 1 {
                let addDepartment = UIButton(type: .system)
                addDepartment.setTitle("＋ Phòng ban", for: .normal)
                addDepartment.addTarget(self, action: #selector(addDepartmentAssignment), for: .touchUpInside)
                addRow.insertArrangedSubview(addDepartment, at: 0)
            }
            rebuildAssignments()
        } catch {
            showError((error as? ConvexException)?.message ?? ConvexHttpClient.humanize(error.localizedDescription))
        }
    }

    /// Creator-based rule from the server: a new admin/mod document, or an edited approval document.
    private var requiresApproval: Bool {
        if let editingWork { return editingWork.requiresApproval || reapproval }
        return options?.requiresApproval ?? false
    }

    /// Admin editing an approved document: the server sends it back to Ban giám hiệu.
    private var reapproval: Bool { WorkApprovalRules.editNeedsReapproval(editingWork) }

    private var approvalNeeded: Bool {
        reapproval || viewModel.approversRequired(requiresApproval: requiresApproval, assignments: assignments)
    }

    private func refreshApprovers() {
        let available = options?.approvers ?? []
        // Edits keep the previous approvers even before options load; unknown ids are dropped once loaded.
        if options != nil {
            approverIds = approverIds.filter { id in available.contains { $0.id == id } }
        }
        approverBlock.isHidden = !requiresApproval
        let required = approvalNeeded
        approverTitle.text = WorkApprovalRules.approverPickerTitle + (required ? " *" : " (không bắt buộc khi chỉ giao cho chính bạn)")
        approverTitle.accessibilityLabel = WorkApprovalRules.approverPickerTitle + (required ? ", bắt buộc" : ", không bắt buộc")
        let names = approverIds.compactMap { id in available.first { $0.id == id }?.name }
        let summary: String
        if options != nil && available.isEmpty {
            summary = "Chưa có thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động."
        } else if approverIds.isEmpty {
            summary = "Chọn người duyệt"
        } else if names.isEmpty {
            summary = "\(approverIds.count) người đã chọn"
        } else {
            summary = "\(approverIds.count) người đã chọn: " + names.joined(separator: ", ")
        }
        approverButton.setTitle(summary, for: .normal)
        approverButton.accessibilityLabel = "Người duyệt. \(summary)"
        approverButton.accessibilityHint = "Mở danh sách Ban giám hiệu để chọn"
        let title = WorkApprovalRules.submitTitle(editing: editingWork != nil, approvalNeeded: requiresApproval && required)
        if !isBusy { submitButton.setTitle(title, for: .normal) }
    }

    @objc private func pickApprovers() {
        let people = options?.approvers ?? []
        let items = people.map { person -> (String, String, String) in
            let detail = [person.level > 0 ? "\(person.level) sao" : "", person.positionName.isEmpty ? "Chưa gán chức vụ" : person.positionName]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return (person.id, person.name, detail)
        }
        let picker = WorkMultiChoiceViewController(
            titleText: WorkApprovalRules.approverPickerTitle,
            note: WorkApprovalRules.approvalNote,
            items: items,
            selected: approverIds
        ) { [weak self] ids in
            self?.approverIds = ids
            self?.refreshApprovers()
        }
        navigationController?.pushViewController(picker, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func addIndividual() {
        var row = WorkCreateAssignment.individual()
        row.deadline = WorkCreatePolicy.formatDeadline(Date())
        assignments.append(row)
        rebuildAssignments()
    }

    @objc private func addDepartmentAssignment() {
        var row = WorkCreateAssignment.department()
        row.deadline = WorkCreatePolicy.formatDeadline(Date())
        assignments.append(row)
        rebuildAssignments()
    }

    private func rebuildAssignments() {
        refreshApprovers()
        assignmentsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if assignments.isEmpty {
            let empty = UILabel()
            empty.text = (options?.canAssignDepartments == true)
                ? "Bấm ＋ Phòng ban hoặc ＋ Cá nhân để thêm người nhận việc."
                : "Bấm ＋ Cá nhân để thêm người nhận việc."
            empty.font = .preferredFont(forTextStyle: .subheadline)
            empty.textColor = .secondaryLabel
            empty.numberOfLines = 0
            assignmentsStack.addArrangedSubview(empty)
            return
        }
        for (index, row) in assignments.enumerated() {
            assignmentsStack.addArrangedSubview(makeAssignmentCard(index: index, row: row))
        }
    }

    private func makeAssignmentCard(index: Int, row: WorkCreateAssignment) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12

        let header = UIStackView()
        header.axis = .horizontal
        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = row.isIndividual ? "Phân công \(index + 1) · Cá nhân" : "Phân công \(index + 1) · Phòng ban"
        title.numberOfLines = 0
        let remove = UIButton(type: .system)
        remove.setTitle("Xóa", for: .normal)
        remove.tag = index
        remove.addTarget(self, action: #selector(removeAssignment(_:)), for: .touchUpInside)
        header.addArrangedSubview(title)
        header.addArrangedSubview(remove)

        let pick = UIButton(type: .system)
        pick.tag = index
        pick.contentHorizontalAlignment = .leading
        pick.addTarget(self, action: #selector(pickTarget(_:)), for: .touchUpInside)
        if row.isIndividual {
            let user = options?.users.first { $0.id == row.userIds.first }
            pick.setTitle(user.map { "\($0.name)\($0.departmentName.isEmpty ? "" : " · \($0.departmentName)")" } ?? "Chọn người nhận", for: .normal)
        } else {
            let department = options?.departments.first { $0.id == row.departmentId }
            pick.setTitle(department?.name ?? "Chọn phòng ban", for: .normal)
        }

        let content = UITextView()
        content.font = .preferredFont(forTextStyle: .body)
        content.adjustsFontForContentSizeCategory = true
        content.layer.borderWidth = 1
        content.layer.borderColor = UIColor.separator.cgColor
        content.layer.cornerRadius = 8
        content.text = row.content
        content.tag = index
        content.delegate = self
        content.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        content.accessibilityLabel = "Nội dung công việc"

        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.timeZone = TimeZone(secondsFromGMT: 7 * 3600)
        datePicker.tag = index
        datePicker.addTarget(self, action: #selector(deadlineChanged(_:)), for: .valueChanged)
        if let parsed = parseDeadline(row.deadline) {
            datePicker.date = parsed
        }

        card.addArrangedSubview(header)
        card.addArrangedSubview(pick)
        card.addArrangedSubview(content)
        card.addArrangedSubview(datePicker)
        return card
    }

    func textViewDidChange(_ textView: UITextView) {
        let index = textView.tag
        guard assignments.indices.contains(index) else { return }
        assignments[index].content = String(textView.text.prefix(2000))
    }

    @objc private func deadlineChanged(_ sender: UIDatePicker) {
        let index = sender.tag
        guard assignments.indices.contains(index) else { return }
        assignments[index].deadline = WorkCreatePolicy.formatDeadline(sender.date)
    }

    @objc private func removeAssignment(_ sender: UIButton) {
        let index = sender.tag
        guard assignments.indices.contains(index) else { return }
        assignments.remove(at: index)
        rebuildAssignments()
    }

    @objc private func pickTarget(_ sender: UIButton) {
        let index = sender.tag
        guard assignments.indices.contains(index) else { return }
        let row = assignments[index]
        let items: [(String, String)]
        if row.isIndividual {
            let selected = Set(assignments.filter(\.isIndividual).flatMap(\.userIds))
            items = (options?.users ?? []).compactMap { user in
                if user.id == row.userIds.first || !selected.contains(user.id) {
                    let label = user.departmentName.isEmpty ? user.name : "\(user.name) · \(user.departmentName)"
                    return (user.id, label)
                }
                return nil
            }
        } else {
            let selected = Set(assignments.filter { !$0.isIndividual }.map(\.departmentId))
            items = (options?.departments ?? []).compactMap { department in
                if department.id == row.departmentId || !selected.contains(department.id) {
                    return (department.id, department.name)
                }
                return nil
            }
        }
        let picker = WorkChoiceViewController(
            titleText: row.isIndividual ? "Chọn người nhận" : "Chọn phòng ban",
            items: items
        ) { [weak self] id in
            guard let self, self.assignments.indices.contains(index) else { return }
            if self.assignments[index].isIndividual {
                self.assignments[index].userIds = [id]
            } else {
                self.assignments[index].departmentId = id
            }
            self.rebuildAssignments()
        }
        navigationController?.pushViewController(picker, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func pickPhoto() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func pickFile() {
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
        present(picker, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func removeFile() {
        fileData = nil
        fileName = ""
        fileMime = ""
        documentTypeId = editingWork?.documentTypeId ?? ""
        refreshFileLabel()
        refreshTypeButton()
    }

    private func refreshFileLabel() {
        if !fileName.isEmpty {
            fileLabel.text = fileName
        } else if !keptFileName.isEmpty {
            fileLabel.text = "Đang giữ tệp hiện tại: \(keptFileName). Chọn tệp mới nếu muốn thay."
        } else {
            fileLabel.text = "Tệp đính kèm (không bắt buộc)"
        }
    }

    @objc private func confirmCancel() {
        let alert = UIAlertController(title: "Bạn có chắc chắn Hủy sửa không?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Hủy sửa", style: .destructive) { [weak self] _ in
            self?.navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        })
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func pickDocumentType() {
        let items = (options?.documentTypes ?? []).map { ($0.id, $0.name) }
        let picker = WorkChoiceViewController(titleText: "Chọn loại văn bản", items: items) { [weak self] id in
            self?.documentTypeId = id
            self?.refreshTypeButton()
        }
        navigationController?.pushViewController(picker, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func refreshTypeButton() {
        let hasFile = fileData != nil || editingWork?.privateFile == true
        typeButton.isHidden = !hasFile
        let name = options?.documentTypes.first { $0.id == documentTypeId }?.name
        typeButton.setTitle(name ?? "Chọn loại văn bản", for: .normal)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        guard Self.allowedUploadExtensions.contains(ext) else {
            showError("Chỉ chấp nhận tệp PDF, DOCX, Excel, PNG hoặc JPG.")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                showError("Tệp rỗng, vui lòng chọn lại.")
                return
            }
            guard data.count <= Self.maxUploadFileSize else {
                showError("Dung lượng tệp tối đa là 20MB.")
                return
            }
            fileData = data
            fileName = url.lastPathComponent
            fileMime = mimeType(for: url)
            fileLabel.text = fileName
            refreshFileLabel()
            refreshTypeButton()
        } catch {
            showError("Không thể đọc tệp đã chọn. Vui lòng thử lại.")
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let itemProvider = result.itemProvider
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            showError("Không thể tải ảnh đã chọn.")
            return
        }
        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self, let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.85) else {
                DispatchQueue.main.async { self?.showError("Không thể đọc ảnh đã chọn.") }
                return
            }
            DispatchQueue.main.async {
                guard data.count <= Self.maxUploadFileSize else {
                    self.showError("Dung lượng ảnh tối đa là 20MB.")
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                self.fileData = data
                self.fileName = "dinh_kem_\(formatter.string(from: Date())).jpg"
                self.fileMime = "image/jpeg"
                self.fileLabel.text = self.fileName
                self.refreshFileLabel()
                self.refreshTypeButton()
            }
        }
    }

    @objc private func submit() {
        guard !isBusy else { return }
        if editingWork != nil {
            let alert = UIAlertController(
                title: "Bạn có chắc chắn Lưu không?",
                message: reapproval ? WorkApprovalRules.reapprovalWarning : nil,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in
                self?.persist()
            })
            present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
            return
        }
        persist()
    }

    private func persist() {
        guard !isBusy else { return }
        hideError()
        if let message = WorkCreatePolicy.validate(
            title: titleField.text ?? "",
            assignments: assignments,
            hasFile: fileData != nil,
            documentTypeId: documentTypeId,
            approversRequired: approvalNeeded,
            approverCount: approverIds.count
        ) {
            showError(message)
            return
        }
        isBusy = true
        submitButton.isEnabled = false
        submitButton.setTitle(editingWork == nil ? "Đang tạo…" : "Đang lưu…", for: .normal)
        spinner.startAnimating()
        let editingDocument = editingWork
        let needsApproval = requiresApproval
        let needsReapproval = reapproval
        let approvers = requiresApproval ? approverIds : []
        Task {
            do {
                if let editingDocument {
                    try await viewModel.submitUpdate(
                        documentId: editingDocument.id,
                        title: titleField.text ?? "",
                        assignments: assignments,
                        fileData: fileData,
                        fileName: fileName.isEmpty ? nil : fileName,
                        mimeType: fileMime.isEmpty ? nil : fileMime,
                        documentTypeId: documentTypeId,
                        requiresApproval: needsApproval,
                        reapproval: needsReapproval,
                        approverUserIds: approvers
                    )
                } else {
                    try await viewModel.submitCreate(
                        title: titleField.text ?? "",
                        assignments: assignments,
                        fileData: fileData,
                        fileName: fileName.isEmpty ? nil : fileName,
                        mimeType: fileMime.isEmpty ? nil : fileMime,
                        documentTypeId: documentTypeId,
                        requiresApproval: needsApproval,
                        approverUserIds: approvers
                    )
                }
                onCreated()
                navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                let fallback = (error as? ConvexException)?.message ?? ConvexHttpClient.humanize(error.localizedDescription)
                if editingDocument != nil {
                    let raw = ((error as? ConvexException)?.code ?? "") + " " + fallback
                    showError(WorkCreatePolicy.actionError(raw: raw, deleting: false, fallback: fallback))
                } else {
                    showError(fallback)
                }
                isBusy = false
                submitButton.isEnabled = true
                refreshApprovers()
                spinner.stopAnimating()
            }
        }
    }

    private func parseDeadline(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    private func hideError() {
        errorLabel.text = nil
        errorLabel.isHidden = true
    }
}

private final class WorkChoiceViewController: UITableViewController {
    private let items: [(String, String)]
    private let onSelect: (String) -> Void

    init(titleText: String, items: [(String, String)], onSelect: @escaping (String) -> Void) {
        self.items = items
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        title = titleText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(items.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Choice") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Choice")
        if items.isEmpty {
            cell.textLabel?.text = "Không còn lựa chọn phù hợp."
            cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = items[indexPath.row].1
            cell.accessoryType = .disclosureIndicator
        }
        cell.textLabel?.numberOfLines = 0
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else { return }
        onSelect(items[indexPath.row].0)
        navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

/// Multi-select list (Ban giám hiệu approvers) with VoiceOver checked state.
private final class WorkMultiChoiceViewController: UITableViewController {
    private let note: String
    private let items: [(String, String, String)]
    private var selected: [String]
    private let onDone: ([String]) -> Void

    init(titleText: String, note: String, items: [(String, String, String)], selected: [String], onDone: @escaping ([String]) -> Void) {
        self.note = note
        self.items = items
        self.selected = selected
        self.onDone = onDone
        super.init(style: .insetGrouped)
        title = titleText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", style: .prominent, target: self, action: #selector(done))
    }

    @objc private func done() {
        onDone(selected)
        navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(items.count, 1) }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "\(selected.count) người đã chọn. \(note)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MultiChoice") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "MultiChoice")
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        guard items.indices.contains(indexPath.row) else {
            cell.textLabel?.text = "Chưa có thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động."
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
        let item = items[indexPath.row]
        let checked = selected.contains(item.0)
        cell.textLabel?.text = item.1
        cell.detailTextLabel?.text = item.2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = checked ? .checkmark : .none
        cell.accessibilityTraits = checked ? [.button, .selected] : [.button]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else { return }
        let id = items[indexPath.row].0
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
        tableView.reloadData()
    }
}
