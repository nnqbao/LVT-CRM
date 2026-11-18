import UIKit

/// In-screen section switcher: N equal-width items, SF Symbol on top + short label below
/// (owner-approved style "E", 2026-10-24). Replaces UISegmentedControl where the labels did not
/// fit: widths never depend on the words, so no item is pushed off screen. Sends `.valueChanged`.
/// Items are plain Auto Layout views (not UIButton configurations) so a label that wraps onto
/// two or three lines at large Dynamic Type sizes always makes the bar taller instead of clipping.
final class IconTabBar: UIControl {
    struct Item {
        let title: String
        let systemImage: String
    }

    private(set) var items: [Item]
    private let stack = UIStackView()
    private var itemViews: [IconTabItemView] = []
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
        stack.alignment = .fill
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
        for (index, item) in items.enumerated() {
            let view = IconTabItemView(item: item)
            view.addAction(UIAction { [weak self] _ in self?.tap(index) }, for: .touchUpInside)
            itemViews.append(view)
            stack.addArrangedSubview(view)
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
        for (index, view) in itemViews.enumerated() {
            view.apply(selected: index == selectedIndex, badge: badges[index])
        }
    }
}

/// One tab: rounded highlight, icon, wrapping label, optional badge on the icon.
private final class IconTabItemView: UIControl {
    private let item: IconTabBar.Item
    private let highlight = UIView()
    private let imageView = UIImageView()
    private let label = UILabel()
    private let badge = UILabel()

    init(item: IconTabBar.Item) {
        self.item = item
        super.init(frame: .zero)
        highlight.isUserInteractionEnabled = false
        highlight.layer.cornerRadius = 19
        highlight.layer.cornerCurve = .continuous
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        let column = UIStackView(arrangedSubviews: [imageView, label])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 3
        column.isUserInteractionEnabled = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .systemRed
        badge.textAlignment = .center
        badge.layer.cornerRadius = 8
        badge.layer.masksToBounds = true
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        NSLayoutConstraint.activate([
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            badge.heightAnchor.constraint(equalToConstant: 16),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            badge.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 6),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(selected: Bool, badge count: Int) {
        // Icon and label grow with Dynamic Type but are capped so five items still fit one row.
        let iconSize = min(UIFont.preferredFont(forTextStyle: .body).pointSize, 22)
        imageView.image = UIImage(systemName: item.systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize))
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            maximumPointSize: 15
        )
        label.text = item.title
        let color: UIColor = selected ? .label : .secondaryLabel
        label.textColor = color
        imageView.tintColor = color
        highlight.backgroundColor = selected ? .systemBackground : .clear
        badge.isHidden = count == 0
        badge.text = count == 0 ? nil : " \(IconTabBar.badgeText(count)) "
        accessibilityLabel = count > 0 ? "\(item.title), \(IconTabBar.badgeText(count))" : item.title
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
