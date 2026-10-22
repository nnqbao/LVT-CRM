import UIKit

@MainActor final class HomeroomDetailViewController: UITableViewController, UISearchBarDelegate {
    private let repository: HomeroomRepository
    private let store: HomeroomDetailStore
    private lazy var dayNavigator = HomeroomDayNavigator(date: store.context.date)
    private let pane = UISegmentedControl(items: ["Điểm danh", "Danh sách lớp"])
    private var dailyPane: Bool { pane.selectedSegmentIndex == 0 }
    private let search = UISearchBar()
    private let historyFrom = UIDatePicker()
    private let historyTo = UIDatePicker()
    private var task: Task<Void, Never>?
    private enum Row {
        case info(String, String?)
        case banner(String, String?, HomeroomTone, String)
        case stats([HomeroomStat])
        case item(title: String, subtitle: String?, chips: [HomeroomChip], leading: String?, studentId: String?)
        case heading(String)
        case absence(DailyRow, canCorrect: Bool)
    }
    private var rows: [Row] = []
    private lazy var writes = repository.writeOperations
    /// Attendance day currently being toggled (one at a time; the switch is disabled meanwhile).
    private var busyDayId: String?
    private var busyUnexcused = false
    private var toggleTask: Task<Void, Never>?
    private var toggleStatus: String?
    var onClassDateChanged: ((String) -> Void)?

    init(repository: HomeroomRepository, context: DetailContext, studentId: String? = nil) {
        self.repository = repository
        store = HomeroomDetailStore(operations: repository.detailOperations, context: context)
        store.studentId = studentId
        super.init(style: .insetGrouped)
        title = studentId == nil ? "Lớp" : "Học sinh"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); toggleTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(retry), for: .valueChanged)
        var barItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(retry))]
        // Sửa is for student contacts only; absences are toggled inline ("Vắng không phép").
        if store.studentId != nil { barItems.append(UIBarButtonItem(title: "Sửa", style: .plain, target: self, action: #selector(edit))) }
        navigationItem.rightBarButtonItems = barItems
        tableView.register(HomeroomStatTilesCell.self, forCellReuseIdentifier: HomeroomStatTilesCell.reuseIdentifier)
        tableView.register(HomeroomListCell.self, forCellReuseIdentifier: HomeroomListCell.reuseIdentifier)
        tableView.register(HomeroomBannerCell.self, forCellReuseIdentifier: HomeroomBannerCell.reuseIdentifier)
        tableView.register(HomeroomAbsenceCell.self, forCellReuseIdentifier: HomeroomAbsenceCell.reuseIdentifier)
        dayNavigator.presenter = self
        dayNavigator.onChange = { [weak self] selected in self?.dateChanged(to: selected) }
        pane.selectedSegmentIndex = 0
        pane.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        pane.addTarget(self, action: #selector(paneChanged), for: .valueChanged)
        search.placeholder = "Tìm học sinh"
        search.searchBarStyle = .minimal
        search.delegate = self
        dayNavigator.isHidden = store.studentId != nil
        pane.isHidden = store.studentId != nil
        search.isHidden = store.studentId != nil
        let fromLabel = UILabel()
        fromLabel.text = "Lịch sử từ ngày"
        let toLabel = UILabel()
        toLabel.text = "Đến ngày"
        for label in [fromLabel, toLabel] {
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            label.isHidden = store.studentId == nil
        }
        for datePicker in [historyFrom, historyTo] {
            datePicker.datePickerMode = .date
            datePicker.preferredDatePickerStyle = .compact
            datePicker.calendar = Calendar(identifier: .gregorian)
            datePicker.timeZone = VietnamDate.timeZone
            datePicker.locale = Locale(identifier: "vi_VN")
            datePicker.isHidden = store.studentId == nil
            datePicker.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            datePicker.addTarget(self, action: #selector(historyChanged), for: .valueChanged)
        }
        historyFrom.date = VietnamDate.date(from: store.context.from) ?? Date()
        historyTo.date = VietnamDate.date(from: store.context.to) ?? Date()
        historyFrom.maximumDate = historyTo.date
        historyTo.minimumDate = historyFrom.date
        historyFrom.accessibilityLabel = "Lịch sử từ ngày"
        historyTo.accessibilityLabel = "Lịch sử đến ngày"
        let controls: [UIView] = store.studentId == nil ? [dayNavigator, pane, search] : [fromLabel, historyFrom, toLabel, historyTo]
        let stack = UIStackView(arrangedSubviews: controls)
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        tableView.tableHeaderView = stack
        store.onChange = { [weak self] in self?.render() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        retry()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        task?.cancel()
        toggleTask?.cancel()
        busyDayId = nil
        store.clear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if header.frame.size != size { header.frame.size = size; tableView.tableHeaderView = header }
    }

    @objc private func retry() {
        toggleStatus = nil
        task?.cancel()
        store.clear()
        task = Task { [weak self] in await self?.store.load() }
    }
    private func dateChanged(to date: String) {
        guard date != store.context.date else { return }
        let current = store.context
        store.context = DetailContext(yearId: current.yearId, classId: current.classId, date: date, from: current.from, to: current.to)
        onClassDateChanged?(date)
        retry()
    }
    @objc private func paneChanged() { render() }
    @objc private func historyChanged() {
        let current = store.context
        let from = VietnamDate.string(from: historyFrom.date)
        let to = VietnamDate.string(from: historyTo.date)
        guard from <= to else { return }
        historyFrom.maximumDate = historyTo.date
        historyTo.minimumDate = historyFrom.date
        store.context = DetailContext(yearId: current.yearId, classId: current.classId, date: current.date, from: from, to: to)
        retry()
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { render() }

    private func matches(_ name: String, _ code: String) -> Bool {
        HomeroomDetailDecoder.matchesStudent(name: name, code: code, search: search.text ?? "")
    }

    private func render() {
        rows = []
        if store.loading {
            rows = [.info("Đang tải…", HomeroomPresentation.dayTitle(store.context.date))]
        } else if let error = store.error {
            rows = [.banner("Chưa tải được dữ liệu", "\(error)\nKéo xuống hoặc nhấn Tải lại để thử lại.", .danger, "exclamationmark.triangle")]
        } else if let data = store.classData {
            let klass = data.scoped.class
            title = klass.name.isEmpty ? klass.code : klass.name
            let teacher = data.scoped.currentTeacherName.isEmpty ? "chưa phân công" : data.scoped.currentTeacherName
            rows.append(.info(klass.name.isEmpty ? "Lớp \(klass.code)" : klass.name, ([HomeroomPresentation.dayTitle(store.context.date), "GVCN \(teacher)"] + (klass.status == "archived" ? ["Lớp đã lưu trữ"] : [])).joined(separator: " · ")))
            if dailyPane {
                renderDaily(data.daily)
            } else {
                let visible = data.roster.rows.filter { matches($0.student.fullName, $0.student.studentCode) }
                rows.append(.info("\(visible.count) học sinh", nil))
                if visible.isEmpty { rows.append(.info(data.roster.rows.isEmpty ? "Lớp chưa có học sinh" : "Không tìm thấy học sinh", nil)) }
                rows += visible.map { .item(title: $0.student.fullName, subtitle: "Mã \($0.student.studentCode)", chips: [], leading: $0.enrollment.rosterNumber.map(String.init) ?? "—", studentId: $0.student._id) }
            }
        } else if let data = store.studentData {
            let student = data.profile.student
            title = "Học sinh"
            rows.append(.info(student.fullName, "Mã \(student.studentCode) · Ngày sinh \(student.dateOfBirth.map(VietnamDate.display) ?? "—") · Giới tính \(student.gender ?? "—")"))
            if data.profile.showContacts {
                rows.append(.item(title: "Điện thoại học sinh", subtitle: data.profile.studentPhone ?? "—", chips: [], leading: nil, studentId: nil))
                rows += data.profile.guardians.map { .item(title: "\($0.fullName) · \(HomeroomWriteFormViewController.label($0.relationship))", subtitle: $0.phone ?? "—", chips: $0.isPrimaryContact ? [HomeroomChip(text: "Liên hệ chính", tone: .info)] : [], leading: nil, studentId: nil) }
                if data.profile.permissions.canEditContacts { rows.append(.info("Liên hệ · \(data.profile.guardians.count)/6", "Nhấn Sửa để sửa số điện thoại hoặc người giám hộ.")) }
            } else { rows.append(.info("Thông tin liên hệ", "Bạn không có quyền xem thông tin liên hệ.")) }
            rows.append(.info("Quá trình học", nil))
            rows += data.profile.enrollments.map { .item(title: $0.className.isEmpty ? $0.classCode : $0.className, subtitle: "\(VietnamDate.display($0.startDate)) → \($0.endDate.map(VietnamDate.display) ?? "nay")", chips: $0.current ? [HomeroomChip(text: "Hiện tại", tone: .success)] : [], leading: nil, studentId: nil) }
            let history = data.history
            rows.append(.info("Lịch sử điểm danh", "\(VietnamDate.display(store.context.from)) → \(VietnamDate.display(store.context.to)) · \(history.days.count) buổi · \(history.corrections.count) lần điều chỉnh"))
            if history.days.isEmpty { rows.append(.info("Chưa có buổi điểm danh nào trong khoảng này", nil)) }
            rows += history.days.reversed().map { day in
                let time = day.rawObservedAt.map(HomeroomPresentation.clock)
                let detail = [time, day.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return .item(title: HomeroomPresentation.dayTitle(day.attendanceDate), subtitle: detail.isEmpty ? nil : detail, chips: [HomeroomPresentation.studentChip(status: day.effectiveStatus, observedTime: time)], leading: nil, studentId: nil)
            }
            rows += history.corrections.sorted { $0.at > $1.at }.map { .item(title: "Điều chỉnh \(VietnamDate.display($0.attendanceDate))", subtitle: "\(HomeroomDetailDecoder.statusText($0.previousEffectiveStatus)) → \(HomeroomDetailDecoder.statusText($0.nextEffectiveStatus)) · \(timestamp($0.at))", chips: [], leading: nil, studentId: nil) }
        }
        if !store.loading { refreshControl?.endRefreshing() }
        tableView.reloadData()
        if store.studentId != nil {
            navigationItem.rightBarButtonItems?.last?.isEnabled = store.studentData.map { $0.profile.showContacts && $0.profile.permissions.canEditContacts } ?? false
        }
    }

    /// GVCN class day (web AttendanceTab): absentees first and highlighted, then everybody present.
    private func renderDaily(_ daily: ClassDaily) {
        let today = VietnamDate.today()
        if daily.schoolDay.outsideYear { rows.append(.banner("Ngoài năm học", "Không cần điểm danh.", .info, "calendar.badge.exclamationmark")) }
        if daily.rows.isEmpty {
            rows.append(.info("Lớp không có học sinh vào ngày này.", nil))
            return
        }
        if HomeroomPresentation.classNotMarked(daily) {
            let detail = daily.schoolDay.isSchoolDay
                ? "Khi Giám thị lưu điểm danh, học sinh vắng sẽ hiện ở đầu danh sách để bạn đánh dấu vắng không phép."
                : "Đây không phải ngày học."
            rows.append(.banner(HomeroomPresentation.notMarkedMessage(date: store.context.date, today: today), detail, .neutral, "clock"))
            return
        }
        if !daily.schoolDay.isSchoolDay, !daily.schoolDay.outsideYear {
            rows.append(.banner("Không phải ngày học", daily.schoolDay.note ?? "Theo lịch, đây không phải ngày học.", .info, "calendar.badge.minus"))
        }
        rows.append(.stats(HomeroomPresentation.dailyStats(daily.rows.map { $0.day?.effectiveStatus ?? "no_data" })))
        if let saved = daily.classSaved { rows.append(.info(HomeroomPresentation.savedByText(saved), nil)) }
        if let toggleStatus { rows.append(.banner(toggleStatus, nil, .info, "info.circle")) }
        let visible = daily.rows.filter { matches($0.student.fullName, $0.student.studentCode) }
        let split = HomeroomPresentation.splitAttendance(visible)
        let canCorrect = daily.canCorrect && !daily.archived
        if !canCorrect, !daily.archived, !split.absent.isEmpty {
            rows.append(.banner("Chỉ GVCN của lớp (hoặc quản trị viên) mới đánh dấu được vắng không phép.", nil, .neutral, "eye"))
        }
        if visible.isEmpty {
            rows.append(.info("Không tìm thấy học sinh", nil))
            return
        }
        rows.append(.heading("Vắng (\(split.absent.count))"))
        if split.absent.isEmpty { rows.append(.info("Không có học sinh vắng.", nil)) }
        rows += split.absent.map { .absence($0, canCorrect: canCorrect && $0.day != nil) }
        rows.append(.heading("Có mặt (\(split.others.count))"))
        rows += split.others.map { row in
            let record = row.day
            let chip = HomeroomPresentation.studentChip(status: record?.effectiveStatus ?? "no_data", observedTime: record?.rawObservedAt.map(HomeroomPresentation.clock))
            return .item(title: row.student.fullName, subtitle: record?.note, chips: [chip], leading: row.enrollment.rosterNumber.map(String.init) ?? "—", studentId: row.student._id)
        }
    }

    /// "Vắng không phép" switch → studentAttendance.setDisposition (unexcused ↔ excused), reason optional.
    private func toggleUnexcused(_ row: DailyRow, unexcused: Bool) {
        guard busyDayId == nil, let day = row.day, store.studentId == nil, !store.loading else { render(); return }
        let context = store.context
        let write: HomeroomWrite
        do {
            write = try HomeroomWritePayload.disposition(
                AbsenceTarget(id: day._id, studentId: row.student._id, context: context),
                next: HomeroomPresentation.nextDisposition(unexcused: unexcused),
                reason: day.reasonCode ?? "",
                note: day.note ?? ""
            )
        } catch {
            presentToggleError(error.localizedDescription)
            render()
            return
        }
        busyDayId = day._id
        busyUnexcused = unexcused
        toggleStatus = nil
        render()
        let name = row.student.fullName
        toggleTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await writes.submit(write, isCurrent: { [weak self] in
                    self?.store.context == context && self?.store.studentId == nil && self?.store.error == nil
                })
                busyDayId = nil
                toggleStatus = "\(name): \(unexcused ? "vắng không phép" : "vắng có phép")."
                await store.load(keepingData: true)
                UIAccessibility.post(notification: .announcement, argument: toggleStatus)
            } catch is CancellationError {
                busyDayId = nil
            } catch {
                busyDayId = nil
                presentToggleError(error.localizedDescription)
                await store.load(keepingData: true)
            }
        }
    }

    private func presentToggleError(_ message: String) {
        let alert = UIAlertController(title: "Chưa lưu được", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func edit() {
        let context = store.context
        if let data = store.studentData, data.profile.showContacts, data.profile.permissions.canEditContacts {
            let chooser = UIAlertController(title: "Liên hệ · \(data.profile.guardians.count)/6", message: "Liên hệ chính do máy chủ quyết định.", preferredStyle: .actionSheet)
            chooser.addAction(UIAlertAction(title: "Sửa điện thoại học sinh", style: .default) { [weak self] _ in self?.showContact(context, profile: data.profile, guardian: nil, mode: "phone") })
            if data.profile.guardians.count < 6 { chooser.addAction(UIAlertAction(title: "Thêm người giám hộ", style: .default) { [weak self] _ in self?.showContact(context, profile: data.profile, guardian: nil, mode: "guardian") }) }
            for guardian in data.profile.guardians { chooser.addAction(UIAlertAction(title: "Sửa hoặc xóa · \(guardian.fullName)", style: .default) { [weak self] _ in self?.showContact(context, profile: data.profile, guardian: guardian, mode: "guardian") }) }
            chooser.addAction(UIAlertAction(title: "Hủy", style: .cancel)); chooser.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last; present(chooser, animated: true)
        }
    }
    private func showContact(_ context: DetailContext, profile: StudentProfile, guardian: StudentProfile.Guardian?, mode: String) {
        let id = profile.student._id
        let form = HomeroomWriteFormViewController(repository: writes, context: context, studentId: id, guardian: guardian, mode: mode, initialPhone: profile.studentPhone ?? "", isCurrent: { [weak self] in self?.store.context == context && self?.store.studentId == id && self?.store.error == nil }, onClear: { [weak self] in self?.store.clear() }, onRefresh: { [weak self] in await self?.store.load() })
        present(UINavigationController(rootViewController: form), animated: true)
    }

    private func timestamp(_ milliseconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = VietnamDate.timeZone
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case let .info(title, detail):
            let cell = tableView.dequeueReusableCell(withIdentifier: "detail") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "detail")
            var content = cell.defaultContentConfiguration()
            content.text = title
            content.secondaryText = detail
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        case let .banner(title, message, tone, symbol):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomBannerCell.reuseIdentifier, for: indexPath) as! HomeroomBannerCell
            cell.configure(title: title, message: message, tone: tone, symbol: symbol)
            return cell
        case let .stats(stats):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomStatTilesCell.reuseIdentifier, for: indexPath) as! HomeroomStatTilesCell
            cell.configure(stats, footnote: nil)
            return cell
        case let .item(title, subtitle, chips, leading, studentId):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomListCell.reuseIdentifier, for: indexPath) as! HomeroomListCell
            cell.configure(title: title, subtitle: subtitle, chips: chips, leading: leading, tappable: studentId != nil)
            return cell
        case let .heading(text):
            let cell = tableView.dequeueReusableCell(withIdentifier: "heading") ?? UITableViewCell(style: .default, reuseIdentifier: "heading")
            var content = cell.defaultContentConfiguration()
            content.text = text
            content.textProperties.font = .preferredFont(forTextStyle: .title3)
            content.textProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            cell.accessibilityTraits = .header
            return cell
        case let .absence(row, canCorrect):
            let cell = tableView.dequeueReusableCell(withIdentifier: HomeroomAbsenceCell.reuseIdentifier, for: indexPath) as! HomeroomAbsenceCell
            let record = row.day
            let note = [record?.reasonCode, record?.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            cell.configure(
                number: row.enrollment.rosterNumber.map(String.init) ?? "—",
                name: row.student.fullName,
                detail: note.isEmpty ? row.student.studentCode : note,
                chip: HomeroomPresentation.studentChip(status: record?.effectiveStatus ?? "no_data", observedTime: nil),
                canToggle: canCorrect,
                unexcused: record?._id != nil && record?._id == busyDayId ? busyUnexcused : HomeroomPresentation.isUnexcused(record),
                busy: record?._id != nil && record?._id == busyDayId
            )
            cell.onToggle = { [weak self] on in self?.toggleUnexcused(row, unexcused: on) }
            return cell
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let studentId: String
        switch rows[indexPath.row] {
        case let .item(_, _, _, _, id?): studentId = id
        case let .absence(row, _): studentId = row.student._id
        default: return
        }
        navigationController?.pushViewController(HomeroomDetailViewController(repository: repository, context: store.context, studentId: studentId), animated: true)
    }
}
