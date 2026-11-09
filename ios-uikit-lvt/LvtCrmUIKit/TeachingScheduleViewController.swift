import UIKit

/// Lớp học › Lịch dạy (teachers:schedule): Danh sách (theo ngày, từng tháng), Tuần (Thứ 2–6 × 10 tiết), Tháng.
@MainActor
final class TeachingScheduleViewController: UIViewController, TeachingYearSection {
    private let repository: TeachingRepository
    private var year: SchoolYear?
    private var data: TeacherSchedule?
    private var catalog: TeachingCatalog?
    private var errorMessage: String?
    private var loading = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var mode: ScheduleMode = .list
    private var anchor = TeachingSchedule.vietnamNow().date

    private let modeControl = UISegmentedControl(items: ScheduleMode.allCases.map(\.title))
    private let stepper = TeachingStepper(previousLabel: "Kỳ trước", nextLabel: "Kỳ sau")
    private let todayButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private let content = UIStackView()

    init(repository: TeachingRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Tải lại", style: .plain, target: self, action: #selector(reload))]
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.accessibilityLabel = "Dạng xem lịch dạy"
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        stepper.onStep = { [weak self] step in self?.shift(step) }
        var todayConfiguration = UIButton.Configuration.plain()
        todayConfiguration.title = "Hôm nay"
        todayButton.configuration = todayConfiguration
        todayButton.addAction(UIAction { [weak self] _ in self?.goToday() }, for: .touchUpInside)
        todayButton.setContentHuggingPriority(.required, for: .horizontal)
        let stepRow = UIStackView(arrangedSubviews: [stepper, todayButton])
        stepRow.axis = .horizontal
        stepRow.alignment = .center
        stepRow.spacing = 8
        let header = UIStackView(arrangedSubviews: [modeControl, stepRow])
        header.axis = .vertical
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        header.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.refreshControl = UIRefreshControl()
        scroll.refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
        render()
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
            scroll.refreshControl?.endRefreshing()
            render()
            return
        }
        loading = true
        errorMessage = nil
        if data == nil { render() }
        let repository = self.repository
        task = Task { [weak self] in
            do {
                async let schedule = repository.schedule(yearId: year.id)
                async let names = repository.catalog()
                let (loaded, subjects) = try await (schedule, names)
                guard let self, !Task.isCancelled, generation == version else { return }
                if data?.year.id != loaded.year.id { anchor = TeachingSchedule.clamp(TeachingSchedule.vietnamNow().date, to: loaded.year) }
                data = loaded
                catalog = subjects
            } catch {
                guard let self, !Task.isCancelled, generation == version else { return }
                data = nil
                errorMessage = TeachingText.message(error)
            }
            guard let self, generation == version else { return }
            loading = false
            scroll.refreshControl?.endRefreshing()
            render()
        }
    }

    @objc private func modeChanged() {
        mode = ScheduleMode(rawValue: modeControl.selectedSegmentIndex) ?? .list
        render()
    }

    private func shift(_ step: Int) {
        anchor = mode.shift(anchor, by: step)
        render()
        UIAccessibility.post(notification: .layoutChanged, argument: stepper)
    }

    private func goToday() {
        guard let data else { return }
        anchor = TeachingSchedule.clamp(TeachingSchedule.vietnamNow().date, to: data.year)
        render()
    }

    // MARK: Rendering

    private func render() {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let data else {
            stepper.update(title: mode.range(anchor: anchor).label, canPrevious: false, canNext: false)
            todayButton.isHidden = true
            if year == nil { return }
            if loading { content.addArrangedSubview(message("Đang tải lịch dạy…", nil)) }
            else if let errorMessage { content.addArrangedSubview(message("Chưa tải được lịch dạy", "\(errorMessage)\nKéo xuống để thử lại.")) }
            return
        }
        let range = mode.range(anchor: anchor)
        stepper.update(title: range.label, canPrevious: range.from > data.year.startDate, canNext: range.to < data.year.endDate)
        let today = TeachingSchedule.vietnamNow().date
        todayButton.isHidden = anchor == TeachingSchedule.clamp(today, to: data.year)
        guard !data.slots.isEmpty else {
            content.addArrangedSubview(message("Chưa có lịch dạy trong năm học này.", "Quản trị viên xếp lịch tại Thiết lập giáo viên hoặc Thiết lập lịch dạy."))
            return
        }
        let lessons = TeachingSchedule.expandLessons(data.slots, from: range.from, to: range.to, year: data.year, holidays: data.holidays)
        switch mode {
        case .list: renderList(lessons, data: data, today: today)
        case .week: renderWeek(lessons, data: data, from: range.from)
        case .month: renderMonth(lessons, data: data, anchor: anchor, today: today)
        }
    }

    private func subject(_ id: String) -> String { catalog?.subjectName(id) ?? "Môn học" }

    private func label(_ text: String?, _ style: UIFont.TextStyle, color: UIColor = .label, weight: UIFont.Weight? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        if let weight {
            label.font = UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight))
        } else {
            label.font = .preferredFont(forTextStyle: style)
        }
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func card(_ views: [UIView], spacing: CGFloat = 6) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        stack.backgroundColor = .secondarySystemGroupedBackground
        stack.layer.cornerRadius = 12
        stack.layer.cornerCurve = .continuous
        return stack
    }

    private func message(_ title: String, _ detail: String?) -> UIView {
        card([label(title, .headline)] + (detail.map { [label($0, .subheadline, color: .secondaryLabel)] } ?? []))
    }

    /// Danh sách: each day with lessons in the month, in time order.
    private func renderList(_ lessons: [Lesson], data: TeacherSchedule, today: String) {
        var days: [(String, [Lesson])] = []
        for lesson in lessons {
            if days.last?.0 == lesson.date { days[days.count - 1].1.append(lesson) } else { days.append((lesson.date, [lesson])) }
        }
        guard !days.isEmpty else {
            content.addArrangedSubview(message("Không có tiết dạy trong tháng này.", nil))
            return
        }
        for (date, rows) in days {
            let title = label("\(TeachingSchedule.weekdayLabel(date)), \(TeachingSchedule.displayDate(date))", .headline)
            title.accessibilityTraits = .header
            let meta = label("\(date == today ? "Hôm nay · " : "")\(rows.count) tiết", .footnote, color: .secondaryLabel)
            var views: [UIView] = [title, meta]
            for lesson in rows {
                let line = label(nil, .subheadline)
                line.text = "\(TeachingSchedule.periodLabel(lesson)) · \(TeachingSchedule.lessonStartTime(lesson)) — \(data.className(lesson.classId)) · \(subject(lesson.subjectId))"
                views.append(line)
            }
            let view = card(views, spacing: 4)
            if date == today {
                view.layer.borderWidth = 2
                view.layer.borderColor = HomeroomPalette.colors(.info).text.cgColor
            }
            content.addArrangedSubview(view)
        }
    }

    private func gridScroll(_ grid: UIView) -> UIView {
        let horizontal = UIScrollView()
        horizontal.showsHorizontalScrollIndicator = true
        horizontal.alwaysBounceHorizontal = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        horizontal.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: horizontal.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: horizontal.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: horizontal.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: horizontal.contentLayoutGuide.trailingAnchor),
            grid.widthAnchor.constraint(greaterThanOrEqualTo: horizontal.frameLayoutGuide.widthAnchor),
            horizontal.frameLayoutGuide.heightAnchor.constraint(equalTo: grid.heightAnchor),
        ])
        return horizontal
    }

    private func gridCell(_ lines: [String], tone: HomeroomTone?, width: CGFloat, header: Bool = false, accessibility: String? = nil) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        for (index, text) in lines.enumerated() {
            let item = label(text, index == 0 ? .footnote : .caption1, color: index == 0 ? .label : .secondaryLabel, weight: index == 0 && (header || tone != nil) ? .semibold : nil)
            if let tone, index == 0 { item.textColor = HomeroomPalette.colors(tone).text }
            stack.addArrangedSubview(item)
        }
        if let tone {
            stack.backgroundColor = HomeroomPalette.colors(tone).background
            stack.layer.cornerRadius = 8
            stack.layer.cornerCurve = .continuous
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.isAccessibilityElement = !lines.isEmpty
        stack.accessibilityLabel = accessibility ?? lines.joined(separator: ", ")
        return stack
    }

    /// Tuần: rows Tiết 1–5 sáng, Tiết 1–5 chiều; columns Thứ 2–6.
    private func renderWeek(_ lessons: [Lesson], data: TeacherSchedule, from: String) {
        let dates = TeachingSchedule.weekdays.map { TeachingSchedule.addDays(from, $0 - 1) }
        var byKey: [String: Lesson] = [:]
        for lesson in lessons { byKey["\(lesson.date)-\(lesson.session)-\(lesson.period)"] = lesson }
        let columnWidth: CGFloat = max(92, UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 92))
        let headWidth: CGFloat = max(96, UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 96))
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 4
        let headRow = UIStackView(arrangedSubviews: [gridCell(["Tiết"], tone: nil, width: headWidth, header: true)] + dates.map { date in
            gridCell([TeachingSchedule.weekdayLabel(date), String(TeachingSchedule.displayDate(date).prefix(5))], tone: nil, width: columnWidth, header: true,
                     accessibility: "\(TeachingSchedule.weekdayLabel(date)), \(TeachingSchedule.displayDate(date))")
        })
        headRow.axis = .horizontal
        headRow.spacing = 4
        headRow.alignment = .top
        grid.addArrangedSubview(headRow)
        for session in TeachingSchedule.sessions {
            if session == "afternoon" {
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                grid.addArrangedSubview(divider)
            }
            for period in TeachingSchedule.periods {
                let periodTitle = "Tiết \(period)"
                let detail = "\(TeachingSchedule.sessionLabel(session)) · \(TeachingSchedule.lessonStartTime(session: session, period: period))"
                var cells: [UIView] = [gridCell([periodTitle, detail], tone: nil, width: headWidth, header: true)]
                for date in dates {
                    let off = data.holidays.contains(date) || date < data.year.startDate || date > data.year.endDate
                    let place = "\(TeachingSchedule.weekdayLabel(date)), \(TeachingSchedule.periodLabel(session: session, period: period))"
                    if let lesson = byKey["\(date)-\(session)-\(period)"] {
                        let className = data.className(lesson.classId), subjectName = subject(lesson.subjectId)
                        cells.append(gridCell([className, subjectName], tone: .info, width: columnWidth, accessibility: "\(place), \(className), \(subjectName)"))
                    } else if off, session == "morning", period == 1 {
                        cells.append(gridCell(["Nghỉ"], tone: .neutral, width: columnWidth, accessibility: "\(TeachingSchedule.weekdayLabel(date)), nghỉ"))
                    } else {
                        cells.append(gridCell([], tone: nil, width: columnWidth))
                    }
                }
                let row = UIStackView(arrangedSubviews: cells)
                row.axis = .horizontal
                row.spacing = 4
                row.alignment = .fill
                grid.addArrangedSubview(row)
            }
        }
        content.addArrangedSubview(gridScroll(grid))
        if lessons.isEmpty { content.addArrangedSubview(message("Không có tiết dạy trong tuần này.", nil)) }
    }

    /// Tháng: Thứ 2–6 columns; each day lists "S3 · 6A1" / "C1 · 7A2"; holidays read "Nghỉ".
    private func renderMonth(_ lessons: [Lesson], data: TeacherSchedule, anchor: String, today: String) {
        let monthFrom = TeachingSchedule.monthStart(anchor)
        var byDate: [String: [Lesson]] = [:]
        for lesson in lessons { byDate[lesson.date, default: []].append(lesson) }
        let columnWidth: CGFloat = max(84, UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 84))
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 4
        let headRow = UIStackView(arrangedSubviews: TeachingSchedule.weekdays.map {
            gridCell([TeachingSchedule.weekdayLabels[$0] ?? ""], tone: nil, width: columnWidth, header: true)
        })
        headRow.axis = .horizontal
        headRow.spacing = 4
        grid.addArrangedSubview(headRow)
        let dates = TeachingSchedule.monthGridDates(anchor)
        var index = 0
        while index < dates.count {
            let week = Array(dates[index..<min(index + 5, dates.count)])
            index += 5
            let cells: [UIView] = week.map { date in
                if date < monthFrom { return gridCell([], tone: nil, width: columnWidth) }
                let off = data.holidays.contains(date) || date < data.year.startDate || date > data.year.endDate
                let rows = byDate[date] ?? []
                var lines = ["\(Int(date.suffix(2)) ?? 0)"]
                if off { lines.append("Nghỉ") }
                lines += rows.map { "\($0.session == "morning" ? "S" : "C")\($0.period) · \(data.className($0.classId))" }
                let spoken = "\(TeachingSchedule.weekdayLabel(date)), \(TeachingSchedule.displayDate(date))"
                    + (date == today ? ", hôm nay" : "") + (off ? ", nghỉ" : "")
                    + (rows.isEmpty ? "" : ", " + rows.map { "\(TeachingSchedule.periodLabel($0)) \(data.className($0.classId))" }.joined(separator: ", "))
                let tone: HomeroomTone? = date == today ? .info : (off ? .neutral : nil)
                let cell = gridCell(lines, tone: tone, width: columnWidth, accessibility: spoken)
                if tone == nil {
                    cell.backgroundColor = .secondarySystemGroupedBackground
                    cell.layer.cornerRadius = 8
                    cell.layer.cornerCurve = .continuous
                }
                return cell
            }
            let row = UIStackView(arrangedSubviews: cells)
            row.axis = .horizontal
            row.spacing = 4
            row.alignment = .fill
            grid.addArrangedSubview(row)
        }
        content.addArrangedSubview(gridScroll(grid))
    }
}
