import UIKit

/// In-screen section switcher: N equal-width items, SF Symbol on top + short label below
/// (owner-approved style "E", 2026-10-24). Replaces UISegmentedControl where the labels did not
/// fit: widths never depend on the words, so no item is pushed off screen. Sends `.valueChanged`.
final class IconTabBar: UIControl {
    struct Item {
        let title: String
        let systemImage: String
    }

    private(set) var items: [Item]
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private var badgeLabels: [UILabel] = []
    private var badges: [Int]

    var selectedIndex: Int {
        didSet {
            if selectedIndex != oldValue { refresh() }
        }
    }

    init(items: [Item], selectedIndex: Int = 0) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.badges = Array(repeating: 0, count: items.count)
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        for (index, _) in items.enumerated() {
            let button = UIButton(configuration: .plain())
            button.tag = index
            button.addAction(UIAction { [weak self] _ in self?.tap(index) }, for: .touchUpInside)
            button.configurationUpdateHandler = { [weak self] button in self?.style(button) }
            let badge = UILabel()
            badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = .systemRed
            badge.textAlignment = .center
            badge.layer.cornerRadius = 8
            badge.layer.masksToBounds = true
            badge.isHidden = true
            badge.isAccessibilityElement = false
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.heightAnchor.constraint(equalToConstant: 16),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
                badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
                badge.leadingAnchor.constraint(equalTo: button.centerXAnchor, constant: 6),
            ])
            buttons.append(button)
            badgeLabels.append(badge)
            stack.addArrangedSubview(button)
        }
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.refresh()
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Small red count on the item's icon (0 hides it; capped at 99+).
    func setBadge(_ count: Int, at index: Int) {
        guard badges.indices.contains(index) else { return }
        badges[index] = max(0, count)
        refresh()
    }

    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private func tap(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        sendActions(for: .valueChanged)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func refresh() {
        for (index, button) in buttons.enumerated() {
            let count = badges[index]
            badgeLabels[index].isHidden = count == 0
            badgeLabels[index].text = count == 0 ? nil : " \(Self.badgeText(count)) "
            button.isSelected = index == selectedIndex
            button.accessibilityLabel = count > 0 ? "\(items[index].title), \(Self.badgeText(count))" : items[index].title
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
            button.setNeedsUpdateConfiguration()
        }
    }

    private func style(_ button: UIButton) {
        let index = button.tag
        guard items.indices.contains(index) else { return }
        let selected = index == selectedIndex
        var config = UIButton.Configuration.plain()
        // Icon and label grow with Dynamic Type but are capped so five items still fit one row.
        config.image = UIImage(
            systemName: items[index].systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: min(UIFont.preferredFont(forTextStyle: .body).pointSize, 22))
        )
        config.imagePlacement = .top
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
        config.titleAlignment = .center
        // Wrap by word onto a second line ("Đã duyệt / hoàn thành") instead of an ellipsis.
        config.titleLineBreakMode = .byWordWrapping
        let font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            maximumPointSize: 15
        )
        config.attributedTitle = AttributedString(items[index].title, attributes: AttributeContainer([.font: font]))
        config.baseForegroundColor = selected ? .label : .secondaryLabel
        config.background.backgroundColor = selected ? .systemBackground : .clear
        config.background.cornerRadius = 19
        button.configuration = config
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
    }
}
