import UIKit

@MainActor
final class HomeroomViewController: UITableViewController {
    private let repository: HomeroomRepository
    private let session: UserSession
    private let yearButton = UIButton(type: .system)
    private lazy var dayNavigator = HomeroomDayNavigator(date: date)
    private var years: [SchoolYear] = []
    private var yearId: String?
    private var date = VietnamDate.today()
    private var overview: HomeroomOverview?
    private var loading = false
    private var errorMessage: String?
    private var loadTask: Task<Void, Never>?
    private var generation = 0
    private enum Row {
        case info(String, String)
        case banner(String, String?, HomeroomTone, String)
        case stats([HomeroomStat], String?)
        case item(title: String, subtitle: String?, chips: [HomeroomChip], classIndex: Int?)
    }
    private var rows: [Row] = []
    private var managementStores: [String: HomeroomManagementStore] = [:]

    init(repository: HomeroomRepository, session: UserSession) {
        self.repository = repository
        self.session = session
        super.init(style: .insetGrouped)
        title = "Lớp chủ nhiệm"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }
    @objc private func manage() {
        guard !loading, session.isOperationalManager, let yearId else { return }
        let requestedDate = date
        let key = "\(yearId)/\(requestedDate)"
        let store = managementStores[key] ?? repository.management(yearId: yearId, date: requestedDate) { [weak self] in self?.yearId == yearId && self?.date == requestedDate }
        managementStores[key] = store
        present(UINavigationController(rootViewController: HomeroomManagementViewController(store: store)), animated: true)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loadTask?.cancel()
        generation += 1
        overview = nil
        rows = []
        tableView.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        tableView.allowsSelection = true
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(retry), for: .valueChanged)
        var barItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(retry))]
        if session.isOperationalManager {
            barItems.append(UIBarButtonItem(title: "Danh mục", style: .plain, target: self, action: #selector(manage)))
        }
        navigationItem.rightBarButtonItems = barItems
        yearButton.showsMenuAsPrimaryAction = true
        yearButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        yearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        yearButton.titleLabel?.numberOfLines = 0
        yearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        tableView.register(HomeroomStatTilesCell.self, forCellReuseIdentifier: HomeroomStatTilesCell.reuseIdentifier)
        tableView.register(HomeroomListCell.self, forCellReuseIdentifier: HomeroomListCell.reuseIdentifier)
        tableView.register(HomeroomBannerCell.self, forCellReuseIdentifier: HomeroomBannerCell.reuseIdentifier)
        dayNavigator.presenter = self
        dayNavigator.onChange = { [weak self] selected in self?.dateChanged(to: selected) }
        let stack = UIStackView(arrangedSubviews: [yearButton, dayNavigator])
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        tableView.tableHeaderView = stack
        updateHeader()
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

    @objc private func retry() { load() }
    private func dateChanged(to selected: String) {
        guard selected != date else { return }
        managementStores.values.forEach { $0.invalidate() }
        date = selected
        load()
    }

    private func updateHeader() {
        yearButton.setTitle(years.first { $0.id == yearId }.map { "Năm học \($0.name)" } ?? "Chọn năm học", for: .normal)
        yearButton.menu = UIMenu(children: years.map { year in
            UIAction(title: year.name, state: year.id == yearId ? .on : .off) { [weak self] _ in
                guard let self, self.yearId != year.id else { return }
                self.yearId = year.id
                self.managementStores.values.forEach { $0.invalidate() }
                self.updateHeader()
                self.load()
            }
        })
        view.setNeedsLayout()
    }

    private func load() {
        guard session.canSeeHomeroom else {
            overview = nil
            errorMessage = "Bạn không có quyền truy cập Lớp chủ nhiệm."
            render()
            return
        }
        loadTask?.cancel()
        generation += 1
        let version = generation
        let requestedDate = date
        let requestedYear = yearId
        loading = true
        errorMessage = nil
        overview = nil
        render()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedYears = try await repository.listSchoolYears()
                guard !Task.isCancelled, generation == version else { return }
                years = loadedYears
                yearId = loadedYears.first { $0.id == requestedYear }?.id
                    ?? loadedYears.first { $0.active }?.id ?? loadedYears.first?.id
                updateHeader()
                if let selectedYear = yearId {
                    let result = try await repository.overview(schoolYearId: selectedYear, date: requestedDate)
                    guard !Task.isCancelled, generation == version else { return }
                    guard result.date == requestedDate, result.schoolYear.id == selectedYear else {
                        throw ConvexException(code: "INVALID_RESPONSE", message: "Phản hồi không khớp năm học/ngày đã chọn.")
                    }
                    overview = result
                }
                loading = false
                updateHeader()
                refreshControl?.endRefreshing()
                render()
            } catch {
                guard !Task.isCancelled, generation == version else { return }
                loading = false
                errorMessage = error.localizedDescription
                refreshControl?.endRefreshing()
                render()
            }
        }
    }

    private func render() {
        rows = []
        if loading {
            rows = [.info("Đang tải lớp chủ nhiệm…", HomeroomPresentation.dayTitle(date))]
        } else if let errorMessage {
            rows = [.banner("Chưa tải được dữ liệu", "\(errorMessage)\nKéo xuống hoặc nhấn Tải lại để thử lại.", .danger, "exclamationmark.triangle")]
        } else if years.isEmpty {
            rows = [.banner("Chưa có năm học", "Quản trị viên cần tạo năm học trước khi điểm danh.", .neutral, "calendar")]
        } else if let overview {
            let schoolDay = overview.schoolDay.isSchoolDay && !overview.schoolDay.outsideYear
            if overview.schoolDay.outsideYear {
                rows.append(.banner("Ngoài năm học", "Ngày đã chọn nằm ngoài năm học \(overview.schoolYear.name).", .info, "calendar.badge.exclamationmark"))
            } else if !overview.schoolDay.isSchoolDay {
                rows.append(.banner(overview.date == overview.today ? "Hôm nay không phải ngày học" : "Không phải ngày học", overview.schoolDay.note.isEmpty ? "Không cần điểm danh." : overview.schoolDay.note, .info, "calendar.badge.minus"))
            } else {
                rows.append(.stats(HomeroomPresentation.overviewStats(overview.counts), HomeroomPresentation.overviewSummary(studentCount: overview.studentCount, classCount: overview.classes.count, attendanceRate: overview.attendanceRate, ratedRows: overview.ratedRows)))
            }
            if schoolDay, overview.missingUploadShouldAlert {
                rows.append(.banner("Còn \(overview.missingClassCodes.count) lớp chưa có dữ liệu", "Đã quá \(overview.missingUploadCutoffTime): \(overview.missingClassCodes.joined(separator: ", "))", .warning, "exclamationmark.triangle"))
            }
            if overview.classes.isEmpty {
                rows.append(.banner("Chưa có lớp", "Bạn chưa được phân công lớp chủ nhiệm trong ngày này.", .neutral, "person.3"))
            }
            rows += overview.classes.enumerated().map { index, klass in
                .item(title: HomeroomPresentation.classTitle(klass), subtitle: HomeroomPresentation.classSubtitle(klass), chips: HomeroomPresentation.classChips(klass, schoolDay: schoolDay), classIndex: index)
            }
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case let .info(title, detail):
            let cell = tableView.dequeueReusableCell(withIdentifier: "homeroom") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "homeroom")
            var content = cell.defaultContentConfiguration()
            content.text = title
            content.secondaryText = detail
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        case let .banner(title, message, tone, symbol):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
            cell.configure(title: title, message: message, tone: tone, symbol: symbol)
            return cell
        case let .stats(stats, footnote):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomStatTilesCell.reuseIdentifier, for: indexPath) as! HomeroomStatTilesCell
            cell.configure(stats, footnote: footnote)
            return cell
        case let .item(title, subtitle, chips, classIndex):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomListCell.reuseIdentifier, for: indexPath) as! HomeroomListCell
            cell.configure(title: title, subtitle: subtitle, chips: chips, tappable: classIndex != nil)
            return cell
        }
    }

    private func classAt(_ row: Int) -> HomeroomClassSummary? {
        guard !loading, errorMessage == nil,
              let overview, row < rows.count, case let .item(_, _, _, classIndex?) = rows[row], classIndex < overview.classes.count else { return nil }
        return overview.classes[classIndex]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let klass = classAt(indexPath.row), let year = years.first(where: { $0.id == yearId }) else { return }
        let context = DetailContext(yearId: year.id, classId: klass.id, date: date, from: year.startDate, to: year.endDate)
        let controller = HomeroomDetailViewController(repository: repository, context: context)
        controller.onClassDateChanged = { [weak self] selected in
            self?.date = selected
            self?.dayNavigator.setDate(selected)
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
