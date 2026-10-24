import QuickLook
import UIKit

/// Lịch công tác chung as a day-by-day list. Văn thư (admin/mod) submits and edits,
/// BGH approves or returns the whole week, everybody else reads the approved copy.
@MainActor
final class SharedDutyScheduleViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource {
    private enum Section {
        case status
        case notice
        case day(DutyWeekPresentation.Day)
    }

    private let repository: DutiesRepository
    private var weekStart: String
    private var data: SharedDutyWeek?
    private var sections: [Section] = []
    private var feedback: String?
    private var busy = false
    private var loadToken = 0
    private var previewURL: URL?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let weekLabel = UILabel()
    private let actionBar = UIStackView()
    private let actionContainer = UIView()
    private let refresh = UIRefreshControl()

    init(repository: DutiesRepository, weekStart: String? = nil) {
        self.repository = repository
        self.weekStart = DutyWeekPresentation.weekStart(weekStart ?? DutyWeekPresentation.todayIso())
        super.init(nibName: nil, bundle: nil)
        title = "Lịch công tác chung"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        let pdf = UIBarButtonItem(image: UIImage(systemName: "doc.richtext"), style: .plain, target: self, action: #selector(openPdf))
        pdf.accessibilityLabel = "Xem PDF"
        navigationItem.rightBarButtonItem = pdf

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DutyWeekStatusCell.self, forCellReuseIdentifier: DutyWeekStatusCell.reuseIdentifier)
        tableView.register(SharedDutyEventCell.self, forCellReuseIdentifier: SharedDutyEventCell.reuseIdentifier)
        tableView.register(HomeroomBannerCell.self, forCellReuseIdentifier: HomeroomBannerCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "empty")
        tableView.tableHeaderView = makeWeekHeader()
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh

        actionBar.axis = .horizontal
        actionBar.spacing = 10
        actionBar.distribution = .fillEqually
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.backgroundColor = .secondarySystemGroupedBackground
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.addSubview(actionBar)
        actionContainer.isHidden = true

        view.addSubview(tableView)
        view.addSubview(actionContainer)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionContainer.topAnchor),
            actionContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionBar.topAnchor.constraint(equalTo: actionContainer.topAnchor, constant: 12),
            actionBar.leadingAnchor.constraint(equalTo: actionContainer.layoutMarginsGuide.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: actionContainer.layoutMarginsGuide.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        render()
        reload()
    }

    /// Opens a given week (from an approval notification).
    func show(weekStart anchor: String) {
        weekStart = DutyWeekPresentation.weekStart(anchor)
        data = nil
        guard isViewLoaded else { return }
        render()
        reload()
    }

    private func makeWeekHeader() -> UIView {
        let previous = UIButton(type: .system)
        previous.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        previous.accessibilityLabel = "Tuần trước"
        previous.addAction(UIAction { [weak self] _ in self?.shift(-1) }, for: .touchUpInside)
        let next = UIButton(type: .system)
        next.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        next.accessibilityLabel = "Tuần sau"
        next.addAction(UIAction { [weak self] _ in self?.shift(1) }, for: .touchUpInside)
        for button in [previous, next] {
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        weekLabel.font = .preferredFont(forTextStyle: .headline)
        weekLabel.adjustsFontForContentSizeCategory = true
        weekLabel.textAlignment = .center
        weekLabel.isUserInteractionEnabled = true
        weekLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(jumpToday)))
        weekLabel.accessibilityHint = "Chạm để về tuần này"
        let row = UIStackView(arrangedSubviews: [previous, weekLabel, next])
        row.axis = .horizontal
        row.alignment = .center
        row.frame = CGRect(x: 0, y: 0, width: 320, height: 52)
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
        return row
    }

    private func shift(_ direction: Int) {
        weekStart = DutyWeekPresentation.shiftWeek(weekStart, direction)
        data = nil
        feedback = nil
        render()
        reload()
    }

    @objc private func jumpToday() {
        weekStart = DutyWeekPresentation.weekStart(DutyWeekPresentation.todayIso())
        data = nil
        render()
        reload()
    }

    @objc private func reload() {
        loadToken += 1
        let token = loadToken
        let start = weekStart
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await repository.sharedWeek(weekStart: start, weekEnd: DutyWeekPresentation.weekEnd(start))
                guard token == loadToken else { return }
                data = result
            } catch {
                guard token == loadToken else { return }
                feedback = (error as? LocalizedError)?.errorDescription ?? "Không tải được lịch công tác chung. Hãy thử lại."
            }
            refresh.endRefreshing()
            render()
        }
    }

    private func render() {
        weekLabel.text = DutyWeekPresentation.weekLabel(weekStart)
        sections = []
        if let data {
            if let week = data.week, data.viewer != "public", !(week.status == "empty" && !data.canSubmit) {
                sections.append(.status)
            }
            if DutyWeekPresentation.showUnapprovedNotice(viewer: data.viewer, eventCount: data.events.count) {
                sections.append(.notice)
            } else {
                sections += DutyWeekPresentation.days(weekStart: weekStart, events: data.events).map { .day($0) }
            }
        }
        tableView.reloadData()
        renderActions()
    }

    private func renderActions() {
        actionBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let week = data?.week
        if DutyWeekPresentation.canDecide(week, canReview: data?.canReview == true) {
            actionBar.addArrangedSubview(button("Trả lại", filled: false, destructive: true) { [weak self] in self?.confirmReturn() })
            actionBar.addArrangedSubview(button("Duyệt lịch tuần", filled: true) { [weak self] in self?.confirmApprove() })
        } else if let week, DutyWeekPresentation.canSubmit(week, canSubmit: data?.canSubmit == true) {
            actionBar.addArrangedSubview(button(DutyWeekPresentation.submitLabel(week), filled: true) { [weak self] in self?.confirmSubmit() })
        }
        actionContainer.isHidden = actionBar.arrangedSubviews.isEmpty
    }

    private func button(_ title: String, filled: Bool, destructive: Bool = false, action: @escaping () -> Void) -> UIButton {
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.bordered()
        configuration.title = title
        configuration.cornerStyle = .large
        if destructive { configuration.baseForegroundColor = .systemRed }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.isEnabled = !busy
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return button
    }

    // MARK: Week actions

    private var rangeText: String { DutyWeekPresentation.weekLabel(weekStart).replacingOccurrences(of: "Tuần ", with: "") }

    private func confirmSubmit() {
        guard let week = data?.week else { return }
        let message = week.missingParticipants > 0
            ? "Còn \(week.missingParticipants) công tác chưa có thành phần. Vẫn nộp Ban Giám hiệu duyệt?"
            : "Ban Giám hiệu sẽ nhận được thông báo."
        let alert = UIAlertController(title: "Nộp lịch tuần \(rangeText)?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Nộp duyệt", style: .default) { [weak self] _ in
            guard let self else { return }
            run(success: "Đã nộp lịch tuần cho Ban Giám hiệu.") { [repository, weekStart] in
                try await repository.submitWeek(weekStart: weekStart)
            }
        })
        present(alert, animated: true)
    }

    private func confirmApprove() {
        guard let submittedAt = data?.week?.submittedAt else { return }
        let alert = UIAlertController(
            title: "Duyệt lịch tuần \(rangeText)?",
            message: "Giáo viên sẽ thấy lịch này và nhận thông báo.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Duyệt", style: .default) { [weak self] _ in
            guard let self else { return }
            run(success: "Đã duyệt lịch tuần.") { [repository, weekStart] in
                try await repository.approveWeek(weekStart: weekStart, submittedAt: submittedAt)
            }
        })
        present(alert, animated: true)
    }

    private func confirmReturn() {
        guard let submittedAt = data?.week?.submittedAt else { return }
        let alert = UIAlertController(
            title: "Trả lại lịch tuần \(rangeText)",
            message: "Văn thư sẽ thấy lý do này để sửa lại.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Lý do (bắt buộc)"
            field.autocapitalizationType = .sentences
        }
        let send = UIAlertAction(title: "Trả lại", style: .destructive) { [weak self, weak alert] _ in
            guard let self else { return }
            let note = String((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            run(success: "Đã trả lại lịch tuần cho văn thư.") { [repository, weekStart] in
                try await repository.returnWeek(weekStart: weekStart, submittedAt: submittedAt, note: note)
            }
        }
        send.isEnabled = false
        NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: alert.textFields?.first, queue: .main) { [weak send, weak alert] _ in
            MainActor.assumeIsolated {
                send?.isEnabled = !(alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(send)
        present(alert, animated: true)
    }

    private func run(success: String, _ action: @escaping @Sendable () async throws -> Void) {
        guard !busy else { return }
        busy = true
        renderActions()
        Task { [weak self] in
            do {
                try await action()
                self?.feedback = success
            } catch {
                self?.feedback = (error as? LocalizedError)?.errorDescription ?? "Không thực hiện được. Hãy thử lại."
            }
            self?.busy = false
            self?.reload()
        }
    }

    // MARK: PDF

    @objc private func openPdf() {
        guard !busy else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { busy = false }
            do {
                let pdf = try await repository.downloadSharedSchedulePdf(mode: "week", anchorIso: weekStart)
                previewURL = pdf.url
                let preview = QLPreviewController()
                preview.dataSource = self
                preview.title = pdf.fileName
                preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
                    image: UIImage(systemName: "square.and.arrow.down"),
                    style: .plain,
                    target: self,
                    action: #selector(sharePdf)
                )
                preview.navigationItem.rightBarButtonItem?.accessibilityLabel = "Tải xuống"
                navigationController?.pushViewController(preview, animated: !UIAccessibility.isReduceMotionEnabled)
            } catch {
                feedback = (error as? LocalizedError)?.errorDescription ?? "Không tải được PDF. Hãy thử lại."
                render()
            }
        }
    }

    @objc private func sharePdf() {
        guard let previewURL else { return }
        let share = UIActivityViewController(activityItems: [previewURL], applicationActivities: nil)
        (navigationController?.visibleViewController ?? self).present(share, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .status, .notice: return 1
        case .day(let day): return max(day.events.count, 1)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if case .day(let day) = sections[section] { return day.title }
        return nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? feedback : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: DutyWeekStatusCell.reuseIdentifier, for: indexPath) as! DutyWeekStatusCell
            if let week = data?.week { cell.configure(week, manager: data?.canSubmit == true) }
            return cell
        case .notice:
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
            cell.configure(
                title: "Lịch tuần này chưa được duyệt",
                message: "Nhà trường sẽ công bố lịch công tác sau khi Ban Giám hiệu duyệt.",
                tone: .neutral,
                symbol: "calendar.badge.clock"
            )
            cell.backgroundColor = .clear
            return cell
        case .day(let day):
            guard indexPath.row < day.events.count else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "Không có công tác"
                content.textProperties.color = .tertiaryLabel
                content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            }
            let event = day.events[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: SharedDutyEventCell.reuseIdentifier, for: indexPath) as! SharedDutyEventCell
            cell.configure(event, editable: isEditable(event))
            return cell
        }
    }

    private func isEditable(_ event: SharedDutyEvent) -> Bool { data?.canSubmit == true && event.canManage }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case .day(let day) = sections[indexPath.section], indexPath.row < day.events.count else { return }
        let event = day.events[indexPath.row]
        guard isEditable(event) else { return }
        let editor = DutyEditViewController(repository: repository, event: event) { [weak self] in
            self?.feedback = "Đã lưu. Thay đổi chờ Ban Giám hiệu duyệt."
            self?.reload()
        }
        navigationController?.pushViewController(editor, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

/// Status card: pill, one line of context, and the list of pending changes.
final class DutyWeekStatusCell: UITableViewCell {
    static let reuseIdentifier = "duty-week-status"
    private let pill = HomeroomPaddedLabel()
    private let message = UILabel()
    private let hint = UILabel()
    private let changes = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        pill.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .bold))
        pill.adjustsFontForContentSizeCategory = true
        pill.layer.cornerRadius = 11
        pill.clipsToBounds = true
        pill.backgroundColor = .systemBackground
        message.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        changes.font = .preferredFont(forTextStyle: .footnote)
        changes.adjustsFontForContentSizeCategory = true
        changes.numberOfLines = 0
        let pillRow = UIStackView(arrangedSubviews: [pill, UIView()])
        let stack = UIStackView(arrangedSubviews: [pillRow, message, hint, changes])
        stack.axis = .vertical
        stack.spacing = 4
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

    func configure(_ week: DutyWeekState, manager: Bool) {
        let colors = HomeroomPalette.colors(DutyWeekPresentation.tone(week.status))
        backgroundColor = colors.background
        pill.text = DutyWeekPresentation.pill(week.status)
        pill.textColor = colors.text
        let copy = manager ? DutyWeekPresentation.managerCopy(week) : DutyWeekPresentation.reviewerCopy(week)
        message.text = copy.text
        hint.text = copy.hint
        hint.isHidden = copy.hint == nil
        let list = week.status == "approved" ? [] : week.changes.prefix(6).map { "\(DutyWeekPresentation.changeLabel($0.kind)) · \($0.title)" }
        let more = week.changes.count > 6 ? ["… và \(week.changes.count - 6) thay đổi khác"] : []
        changes.text = (list + more).joined(separator: "\n")
        changes.isHidden = list.isEmpty
    }
}

/// One duty: time on the left, title with Mới/Sửa tag, then place · participants.
final class SharedDutyEventCell: UITableViewCell {
    static let reuseIdentifier = "shared-duty-event"
    private let time = UILabel()
    private let title = UILabel()
    private let changeTag = HomeroomPaddedLabel()
    private let meta = UILabel()
    private let addHint = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        time.font = .preferredFont(forTextStyle: .subheadline).withWeight(.bold)
        time.adjustsFontForContentSizeCategory = true
        time.textColor = .tintColor
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        title.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        changeTag.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .bold))
        changeTag.adjustsFontForContentSizeCategory = true
        changeTag.layer.cornerRadius = 6
        changeTag.clipsToBounds = true
        changeTag.insets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        changeTag.setContentHuggingPriority(.required, for: .horizontal)
        meta.font = .preferredFont(forTextStyle: .footnote)
        meta.adjustsFontForContentSizeCategory = true
        meta.textColor = .secondaryLabel
        meta.numberOfLines = 0
        addHint.font = .preferredFont(forTextStyle: .footnote).withWeight(.bold)
        addHint.adjustsFontForContentSizeCategory = true
        addHint.text = "+ Thêm thành phần"
        addHint.textColor = HomeroomPalette.colors(.success).text
        let titleRow = UIStackView(arrangedSubviews: [title, changeTag])
        titleRow.spacing = 6
        titleRow.alignment = .firstBaseline
        let texts = UIStackView(arrangedSubviews: [titleRow, meta, addHint])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [time, texts])
        row.spacing = 10
        row.alignment = .firstBaseline
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

    func configure(_ event: SharedDutyEvent, editable: Bool) {
        time.text = DutyWeekPresentation.timeLabel(event)
        title.text = event.title.isEmpty ? event.content : event.title
        let participants = DutyWeekPresentation.participants(event)
        meta.text = [event.locationText.trimmingCharacters(in: .whitespaces), participants].filter { !$0.isEmpty }.joined(separator: " · ")
        meta.isHidden = meta.text?.isEmpty ?? true
        addHint.isHidden = !(editable && !DutyWeekPresentation.hasParticipants(event))
        if let change = event.approvalChange {
            let colors = HomeroomPalette.colors(change == "added" ? .success : .warning)
            changeTag.text = change == "added" ? "Mới" : "Sửa"
            changeTag.textColor = colors.text
            changeTag.backgroundColor = .systemBackground
            changeTag.isHidden = false
            backgroundColor = HomeroomPalette.colors(.warning).background
        } else {
            changeTag.isHidden = true
            backgroundColor = .secondarySystemGroupedBackground
        }
        accessoryType = editable ? .disclosureIndicator : .none
        selectionStyle = editable ? .default : .none
    }
}

/// UILabel with padding, for pills and tags.
final class HomeroomPaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10) { didSet { invalidateIntrinsicContentSize() } }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
