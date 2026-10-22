import UIKit

/// DESIGN.md status colors (homeroom --hr-* palette) with readable dark-mode variants.
enum HomeroomPalette {
    static func colors(_ tone: HomeroomTone) -> (text: UIColor, background: UIColor) {
        switch tone {
        case .success: return (dynamic(0x0E7363, 0x6FD3BE), dynamic(0xE3F4EF, 0x10382F))
        case .warning: return (dynamic(0x7A4B07, 0xF2C46B), dynamic(0xFDF1D8, 0x3D2C0B))
        case .danger: return (dynamic(0xB23A27, 0xFF9C8A), dynamic(0xFBE5DF, 0x43201A))
        case .neutral: return (dynamic(0x5A6B7C, 0xB7C3CE), dynamic(0xEEF2F5, 0x2A3138))
        case .info: return (dynamic(0x28639A, 0x8DBDF0), dynamic(0xE4EEF8, 0x16304A))
        }
    }

    /// Navy primary action (DESIGN.md `--lvt-navy`) with a readable dark-mode variant.
    static let primaryBackground = dynamic(0x14355F, 0x8DBDF0)
    static let primaryForeground = dynamic(0xFFFFFF, 0x0B1A2E)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Rounded status pill ("3 vắng", "Chưa điểm danh").
final class HomeroomChipLabel: UILabel {
    private let insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    init(_ chip: HomeroomChip) {
        super.init(frame: .zero)
        let colors = HomeroomPalette.colors(chip.tone)
        text = chip.text
        textColor = colors.text
        backgroundColor = colors.background
        font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .bold))
        adjustsFontForContentSizeCategory = true
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

/// Row of colored number tiles (Có mặt / Trễ / Vắng / Chưa có) with an optional muted footnote.
final class HomeroomStatTilesCell: UITableViewCell {
    static let reuseIdentifier = "homeroom-stats"
    private let tiles = UIStackView()
    private let footnote = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        tiles.axis = .horizontal
        tiles.spacing = 8
        tiles.distribution = .fillEqually
        footnote.font = .preferredFont(forTextStyle: .footnote)
        footnote.adjustsFontForContentSizeCategory = true
        footnote.textColor = .secondaryLabel
        footnote.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [tiles, footnote])
        stack.axis = .vertical
        stack.spacing = 10
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

    func configure(_ stats: [HomeroomStat], footnote text: String?) {
        tiles.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for stat in stats { tiles.addArrangedSubview(tile(stat)) }
        footnote.text = text
        footnote.isHidden = text?.isEmpty ?? true
    }

    private func tile(_ stat: HomeroomStat) -> UIView {
        let colors = HomeroomPalette.colors(stat.tone)
        let value = UILabel()
        value.text = stat.value
        value.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 20, weight: .heavy))
        value.adjustsFontForContentSizeCategory = true
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.6
        value.textColor = colors.text
        value.textAlignment = .center
        let label = UILabel()
        label.text = stat.label
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.numberOfLines = 2
        label.textColor = colors.text
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [value, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)
        stack.backgroundColor = colors.background
        stack.layer.cornerRadius = 12
        stack.layer.cornerCurve = .continuous
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(stat.label) \(stat.value)"
        return stack
    }
}

/// Two-line list row: optional leading number, title, one muted subtitle, status chips, chevron when tappable.
final class HomeroomListCell: UITableViewCell {
    static let reuseIdentifier = "homeroom-list"
    private let leading = UILabel()
    private let title = UILabel()
    private let subtitle = UILabel()
    private let chips = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        leading.font = .preferredFont(forTextStyle: .subheadline)
        leading.adjustsFontForContentSizeCategory = true
        leading.textColor = .secondaryLabel
        leading.setContentHuggingPriority(.required, for: .horizontal)
        leading.widthAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 1
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 1
        chips.axis = .horizontal
        chips.spacing = 6
        chips.alignment = .center
        chips.setContentHuggingPriority(.required, for: .horizontal)
        chips.setContentCompressionResistancePriority(.required, for: .horizontal)
        let texts = UIStackView(arrangedSubviews: [title, subtitle])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [leading, texts, chips])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title text: String, subtitle detail: String?, chips items: [HomeroomChip], leading number: String? = nil, tappable: Bool) {
        title.text = text
        subtitle.text = detail
        subtitle.isHidden = detail?.isEmpty ?? true
        leading.text = number
        leading.isHidden = number == nil
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items.forEach { chips.addArrangedSubview(HomeroomChipLabel($0)) }
        chips.isHidden = items.isEmpty
        accessoryType = tappable ? .disclosureIndicator : .none
        selectionStyle = tappable ? .default : .none
        accessibilityLabel = ([number, text, detail] + items.map(\.text)).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        isAccessibilityElement = true
        accessibilityTraits = tappable ? .button : .staticText
    }
}

/// Absent student in the GVCN class day: highlighted (icon + status wording + tint, never colour only), with an
/// optional "Vắng không phép" switch. Tapping the row outside the switch opens the student.
final class HomeroomAbsenceCell: UITableViewCell {
    static let reuseIdentifier = "homeroom-absence"
    var onToggle: ((Bool) -> Void)?
    private let icon = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
    private let leading = UILabel()
    private let name = UILabel()
    private let detail = UILabel()
    private let chips = UIStackView()
    private let info = UIStackView()
    private let toggleLabel = UILabel()
    private let toggle = UISwitch()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let toggleRow = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let danger = HomeroomPalette.colors(.danger)
        icon.tintColor = danger.text
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .headline)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        leading.font = .preferredFont(forTextStyle: .subheadline)
        leading.adjustsFontForContentSizeCategory = true
        leading.textColor = .secondaryLabel
        leading.setContentHuggingPriority(.required, for: .horizontal)
        name.font = .preferredFont(forTextStyle: .headline)
        name.adjustsFontForContentSizeCategory = true
        name.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        chips.axis = .horizontal
        chips.spacing = 6
        chips.alignment = .leading
        let chipRow = UIStackView(arrangedSubviews: [chips, UIView()])
        chipRow.axis = .horizontal
        let texts = UIStackView(arrangedSubviews: [name, detail, chipRow])
        texts.axis = .vertical
        texts.spacing = 4
        info.addArrangedSubview(icon)
        info.addArrangedSubview(leading)
        info.addArrangedSubview(texts)
        info.axis = .horizontal
        info.alignment = .firstBaseline
        info.spacing = 8
        info.isAccessibilityElement = true
        info.accessibilityTraits = .button
        info.accessibilityHint = "Mở hồ sơ học sinh"
        toggleLabel.text = "Vắng không phép"
        toggleLabel.font = .preferredFont(forTextStyle: .body)
        toggleLabel.adjustsFontForContentSizeCategory = true
        toggleLabel.numberOfLines = 0
        toggleLabel.isAccessibilityElement = false
        toggle.onTintColor = danger.text
        toggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onToggle?(self.toggle.isOn)
        }, for: .valueChanged)
        spinner.hidesWhenStopped = true
        toggleRow.addArrangedSubview(toggleLabel)
        toggleRow.addArrangedSubview(spinner)
        toggleRow.addArrangedSubview(toggle)
        toggleRow.axis = .horizontal
        toggleRow.alignment = .center
        toggleRow.spacing = 10
        toggleRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [info, toggleRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = danger.background
        backgroundConfiguration = background
        accessoryType = .disclosureIndicator
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(number: String?, name text: String, detail note: String?, chip: HomeroomChip, canToggle: Bool, unexcused: Bool, busy: Bool) {
        leading.text = number
        leading.isHidden = number == nil
        name.text = text
        detail.text = note
        detail.isHidden = note?.isEmpty ?? true
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chips.addArrangedSubview(HomeroomChipLabel(chip))
        toggleRow.isHidden = !canToggle
        toggle.isOn = unexcused
        toggle.isEnabled = !busy
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        info.accessibilityLabel = [number, text, chip.text, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        toggle.accessibilityLabel = "Vắng không phép, \(text)"
        toggle.accessibilityValue = busy ? "Đang lưu" : nil
        accessibilityElements = canToggle ? [info, toggle] : [info]
    }
}

/// Tinted banner with an SF Symbol ("Hôm nay không phải ngày học").
final class HomeroomBannerCell: UITableViewCell {
    static let reuseIdentifier = "homeroom-banner"
    private let icon = UIImageView()
    private let title = UILabel()
    private let message = UILabel()
    private let box = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        let texts = UIStackView(arrangedSubviews: [title, message])
        texts.axis = .vertical
        texts.spacing = 2
        box.addArrangedSubview(icon)
        box.addArrangedSubview(texts)
        box.axis = .horizontal
        box.spacing = 12
        box.alignment = .center
        box.isLayoutMarginsRelativeArrangement = true
        box.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        box.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            box.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title text: String, message detail: String?, tone: HomeroomTone, symbol: String) {
        let colors = HomeroomPalette.colors(tone)
        title.text = text
        message.text = detail
        message.isHidden = detail?.isEmpty ?? true
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = colors.text
        title.textColor = colors.text
        message.textColor = colors.text
        box.backgroundColor = colors.background
        isAccessibilityElement = true
        accessibilityLabel = [text, detail].compactMap { $0 }.joined(separator: ". ")
    }
}

/// "‹ Thứ Sáu, 09/10 ›": arrows move one day; tapping the title opens an inline calendar.
@MainActor final class HomeroomDayNavigator: UIStackView {
    var onChange: ((String) -> Void)?
    weak var presenter: UIViewController?
    private(set) var date: String
    private let titleButton = UIButton(type: .system)

    init(date: String) {
        self.date = date
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        let previous = arrow("chevron.left", label: "Ngày trước", step: -1)
        let next = arrow("chevron.right", label: "Ngày sau", step: 1)
        titleButton.titleLabel?.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .bold))
        titleButton.titleLabel?.adjustsFontForContentSizeCategory = true
        titleButton.setTitleColor(.label, for: .normal)
        titleButton.addTarget(self, action: #selector(openCalendar), for: .touchUpInside)
        titleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        addArrangedSubview(previous)
        addArrangedSubview(titleButton)
        addArrangedSubview(next)
        titleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        update()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDate(_ value: String) {
        date = value
        update()
    }

    private func arrow(_ symbol: String, label: String, step: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.change(to: HomeroomPresentation.shiftDay(self.date, by: step))
        }, for: .touchUpInside)
        return button
    }

    private func update() {
        let title = HomeroomPresentation.dayTitle(date)
        titleButton.setTitle(title, for: .normal)
        titleButton.accessibilityLabel = "Chọn ngày điểm danh, đang chọn \(title)"
    }

    private func change(to value: String) {
        guard value != date else { return }
        date = value
        update()
        onChange?(value)
    }

    @objc private func openCalendar() {
        guard let presenter else { return }
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.calendar = Calendar(identifier: .gregorian)
        picker.timeZone = VietnamDate.timeZone
        picker.locale = Locale(identifier: "vi_VN")
        picker.date = VietnamDate.date(from: date) ?? Date()
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground
        picker.translatesAutoresizingMaskIntoConstraints = false
        sheet.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: sheet.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: sheet.view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: sheet.view.layoutMarginsGuide.trailingAnchor),
        ])
        picker.addAction(UIAction { [weak self, weak sheet] _ in
            self?.change(to: VietnamDate.string(from: picker.date))
            sheet?.dismiss(animated: true)
        }, for: .valueChanged)
        if let controller = sheet.sheetPresentationController {
            controller.detents = [.medium()]
            controller.prefersGrabberVisible = true
        }
        presenter.present(sheet, animated: true)
    }
}
