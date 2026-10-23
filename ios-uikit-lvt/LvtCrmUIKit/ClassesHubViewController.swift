import UIKit

/// A Lớp học section that follows the hub's school year.
@MainActor protocol TeachingYearSection: AnyObject {
    func apply(year: SchoolYear?)
}

/// Lớp học (menu `homeroom`): Tổng quan · Chủ nhiệm · Giảng dạy · Lịch dạy · Học bạ (web HomeroomRouter).
/// "Chủ nhiệm" hosts the existing homeroom screen with its own year/day pickers; the other sections share the
/// school-year menu below the segmented control. Settings (giáo viên, lịch dạy, môn học, loại kiểm tra) stay web-only.
@MainActor
final class ClassesHubViewController: UIViewController {
    enum Section: Int, CaseIterable {
        case overview, homeroom, teaching, schedule, gradebook

        var title: String {
            switch self {
            case .overview: return "Tổng quan"
            case .homeroom: return "Chủ nhiệm"
            case .teaching: return "Giảng dạy"
            case .schedule: return "Lịch dạy"
            case .gradebook: return "Học bạ"
            }
        }

    }

    private let session: UserSession
    private let homeroomRepository: HomeroomRepository
    private let teachingRepository: TeachingRepository
    private let segmented = UISegmentedControl(items: Section.allCases.map(\.title))
    private let segmentScroll = UIScrollView()
    private let yearButton = UIButton(type: .system)
    private let yearStatus = UILabel()
    private let header = UIStackView()
    private let container = UIView()
    private var controllers: [Section: UIViewController] = [:]
    private var current: Section = .overview
    private var years: [SchoolYear] = []
    private var yearId: String?
    private var yearTask: Task<Void, Never>?

    init(session: UserSession, homeroomRepository: HomeroomRepository, teachingRepository: TeachingRepository) {
        self.session = session
        self.homeroomRepository = homeroomRepository
        self.teachingRepository = teachingRepository
        super.init(nibName: nil, bundle: nil)
        title = "Lớp học"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { yearTask?.cancel() }

    var selectedYear: SchoolYear? { years.first { $0.id == yearId } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never

        segmented.selectedSegmentIndex = current.rawValue
        segmented.apportionsSegmentWidthsByContent = true
        segmented.addTarget(self, action: #selector(sectionChanged), for: .valueChanged)
        segmented.accessibilityLabel = "Mục Lớp học"
        applySegmentFont()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.applySegmentFont()
        }
        segmentScroll.showsHorizontalScrollIndicator = false
        segmentScroll.translatesAutoresizingMaskIntoConstraints = false
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmentScroll.addSubview(segmented)

        yearButton.showsMenuAsPrimaryAction = true
        yearButton.contentHorizontalAlignment = .leading
        yearButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        yearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        yearButton.titleLabel?.numberOfLines = 0
        yearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        yearStatus.font = .preferredFont(forTextStyle: .footnote)
        yearStatus.adjustsFontForContentSizeCategory = true
        yearStatus.textColor = .secondaryLabel
        yearStatus.numberOfLines = 0
        yearStatus.isHidden = true

        header.axis = .vertical
        header.spacing = 4
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
        header.addArrangedSubview(segmentScroll)
        header.addArrangedSubview(yearButton)
        header.addArrangedSubview(yearStatus)
        header.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmented.topAnchor.constraint(equalTo: segmentScroll.contentLayoutGuide.topAnchor),
            segmented.bottomAnchor.constraint(equalTo: segmentScroll.contentLayoutGuide.bottomAnchor),
            segmented.leadingAnchor.constraint(equalTo: segmentScroll.contentLayoutGuide.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: segmentScroll.contentLayoutGuide.trailingAnchor),
            segmented.widthAnchor.constraint(greaterThanOrEqualTo: segmentScroll.frameLayoutGuide.widthAnchor),
            segmented.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            segmentScroll.heightAnchor.constraint(equalTo: segmented.heightAnchor),
            container.topAnchor.constraint(equalTo: header.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateYearHeader()
        show(.overview)
        loadYears()
    }

    /// Retry the year list after a failed first load (e.g. offline at launch).
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if years.isEmpty, yearTask == nil { loadYears() }
    }

    private func applySegmentFont() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        segmented.setTitleTextAttributes([.font: font], for: .normal)
        segmented.setTitleTextAttributes([.font: UIFont.preferredFont(forTextStyle: .headline)], for: .selected)
    }

    @objc private func sectionChanged() {
        guard let section = Section(rawValue: segmented.selectedSegmentIndex) else { return }
        show(section)
    }

    private func controller(for section: Section) -> UIViewController {
        if let existing = controllers[section] { return existing }
        let controller: UIViewController
        switch section {
        case .overview:
            controller = TeachingOverviewViewController(
                teachingRepository: teachingRepository,
                homeroomRepository: homeroomRepository,
                openSection: { [weak self] section in self?.select(section) }
            )
        case .homeroom:
            controller = HomeroomViewController(repository: homeroomRepository, session: session)
        case .teaching:
            controller = TeachingClassesViewController(repository: teachingRepository)
        case .schedule:
            controller = TeachingScheduleViewController(repository: teachingRepository)
        case .gradebook:
            controller = GradebookClassesViewController(repository: teachingRepository)
        }
        controllers[section] = controller
        return controller
    }

    func select(_ section: Section) {
        segmented.selectedSegmentIndex = section.rawValue
        show(section)
    }

    private func show(_ section: Section) {
        let next = controller(for: section)
        if let previous = controllers[current], previous !== next, previous.parent === self {
            previous.willMove(toParent: nil)
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        current = section
        if next.parent !== self {
            addChild(next)
            next.view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(next.view)
            NSLayoutConstraint.activate([
                next.view.topAnchor.constraint(equalTo: container.topAnchor),
                next.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                next.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                next.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            next.didMove(toParent: self)
        }
        // The homeroom section keeps its own year and day pickers.
        yearButton.isHidden = section == .homeroom || years.isEmpty
        yearStatus.isHidden = section == .homeroom || yearStatus.text?.isEmpty != false
        navigationItem.rightBarButtonItems = next.navigationItem.rightBarButtonItems
        let helpItems = (navigationItem.leftBarButtonItems ?? []).filter { $0.accessibilityLabel?.hasPrefix("Hướng dẫn:") == true }
        navigationItem.leftBarButtonItems = helpItems
        (next as? TeachingYearSection)?.apply(year: selectedYear)
        if let scroll = (next as? UITableViewController)?.tableView ?? next.view as? UIScrollView {
            setContentScrollView(scroll)
        }
        UIAccessibility.post(notification: .screenChanged, argument: segmented)
    }

    private func loadYears() {
        yearTask?.cancel()
        yearStatus.text = "Đang tải năm học…"
        yearStatus.isHidden = current == .homeroom
        yearTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await teachingRepository.schoolYears()
                guard !Task.isCancelled else { return }
                years = loaded
                let previous = self.yearId
                yearId = loaded.first { $0.id == previous }?.id ?? loaded.first { $0.active }?.id ?? loaded.first?.id
                yearStatus.text = loaded.isEmpty ? "Chưa có năm học. Quản trị viên tạo năm học trước khi dùng Lớp học." : nil
            } catch {
                guard !Task.isCancelled else { return }
                yearStatus.text = "Chưa tải được năm học: \(TeachingText.message(error))"
            }
            yearTask = nil
            updateYearHeader()
            yearButton.isHidden = current == .homeroom || years.isEmpty
            yearStatus.isHidden = current == .homeroom || yearStatus.text?.isEmpty != false
            notifyYear()
        }
    }

    private func notifyYear() {
        for case let section as TeachingYearSection in controllers.values { section.apply(year: selectedYear) }
    }

    private func updateYearHeader() {
        let title = selectedYear.map { "Năm học \($0.name)" } ?? "Chọn năm học"
        yearButton.setTitle(title, for: .normal)
        yearButton.accessibilityLabel = "\(title). Chọn năm học khác"
        yearButton.menu = UIMenu(title: "Năm học", children: years.map { year in
            UIAction(title: year.active ? "\(year.name) · mặc định" : year.name, state: year.id == yearId ? .on : .off) { [weak self] _ in
                guard let self, self.yearId != year.id else { return }
                self.yearId = year.id
                self.updateYearHeader()
                self.notifyYear()
            }
        })
    }
}

// MARK: - Shared Lớp học UI

enum TeachingText {
    static func message(_ error: Error) -> String {
        if let error = error as? ConvexException { return ConvexHttpClient.humanize(error.message) }
        if (error as NSError).domain == NSURLErrorDomain { return "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại." }
        return ConvexHttpClient.humanize(error.localizedDescription)
    }
}

/// Multi-line list row: optional leading time/number, title, subtitle, detail and status chips (text, never colour only).
final class TeachingCell: UITableViewCell {
    static let reuseIdentifier = "teaching-cell"
    private let leadingLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chips = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        leadingLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
        leadingLabel.adjustsFontForContentSizeCategory = true
        leadingLabel.textColor = HomeroomPalette.colors(.info).text
        leadingLabel.setContentHuggingPriority(.required, for: .horizontal)
        leadingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        for label in [titleLabel, subtitleLabel, detailLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }
        chips.axis = .horizontal
        chips.spacing = 6
        chips.alignment = .leading
        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, detailLabel, chips])
        texts.axis = .vertical
        texts.spacing = 3
        texts.alignment = .leading
        let row = UIStackView(arrangedSubviews: [leadingLabel, texts])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(leading: String? = nil, title: String, subtitle: String? = nil, detail: String? = nil, chips items: [HomeroomChip] = [], tappable: Bool, accessibilityLabel label: String? = nil) {
        leadingLabel.text = leading
        leadingLabel.isHidden = leading == nil
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        detailLabel.text = detail
        detailLabel.isHidden = detail?.isEmpty ?? true
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items.forEach { chips.addArrangedSubview(HomeroomChipLabel($0)) }
        chips.isHidden = items.isEmpty
        accessoryType = tappable ? .disclosureIndicator : .none
        selectionStyle = tappable ? .default : .none
        accessibilityLabel = label ?? ([leading, title, subtitle, detail] + items.map(\.text)).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = tappable ? .button : .staticText
    }
}

/// "‹ title ›" period stepper (week / month).
@MainActor final class TeachingStepper: UIStackView {
    var onStep: ((Int) -> Void)?
    private let titleLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    init(previousLabel: String, nextLabel: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 4
        configure(previousButton, symbol: "chevron.left", label: previousLabel, step: -1)
        configure(nextButton, symbol: "chevron.right", label: nextLabel, step: 1)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        addArrangedSubview(previousButton)
        addArrangedSubview(titleLabel)
        addArrangedSubview(nextButton)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, canPrevious: Bool, canNext: Bool) {
        titleLabel.text = title
        previousButton.isEnabled = canPrevious
        nextButton.isEnabled = canNext
    }

    private func configure(_ button: UIButton, symbol: String, label: String, step: Int) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onStep?(step) }, for: .touchUpInside)
    }
}

extension UIViewController {
    func presentTeachingAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: true)
    }

    /// Header that sizes itself to its content (Dynamic Type) for a UITableView.
    func sizeTableHeader(_ tableView: UITableView) {
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
}
