import UIKit

/// Công việc tab (web WorkHub): "Công việc" (work documents) and "Việc của tôi" (private to-dos).
/// Used only when the work menu is visible; when it is hidden the tab shows "Việc của tôi" alone.
@MainActor
final class WorkHubViewController: UIViewController {
    enum Pane: Int { case work, todos }

    let workViewController: WorkViewController
    let todosViewController: PersonalTodosViewController
    private let control = UISegmentedControl(items: ["Công việc", "Việc của tôi"])
    private let container = UIView()
    private(set) var pane: Pane = .work

    init(work: WorkViewController, todos: PersonalTodosViewController) {
        workViewController = work
        todosViewController = todos
        super.init(nibName: nil, bundle: nil)
        title = "Công việc"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always
        control.selectedSegmentIndex = pane.rawValue
        control.accessibilityLabel = "Chọn danh sách"
        control.addAction(UIAction { [weak self] _ in
            guard let self, let pane = Pane(rawValue: control.selectedSegmentIndex) else { return }
            show(pane)
        }, for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            control.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            container.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        workViewController.onBarItemsChange = { [weak self] in self?.syncBarItems() }
        todosViewController.onBarItemsChange = { [weak self] in self?.syncBarItems() }
        embed(pane)
    }

    /// Switch to a pane (also used by notification routing).
    func show(_ next: Pane) {
        loadViewIfNeeded()
        control.selectedSegmentIndex = next.rawValue
        guard next != pane || children.isEmpty else { syncBarItems(); return }
        pane = next
        embed(next)
    }

    private var active: UIViewController { pane == .work ? workViewController : todosViewController }

    private func embed(_ pane: Pane) {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let child = active
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        child.didMove(toParent: self)
        if let scrollView = (child as? UITableViewController)?.tableView {
            setContentScrollView(scrollView, for: .top)
        }
        syncBarItems()
        UIAccessibility.post(notification: .screenChanged, argument: control)
    }

    private func syncBarItems() {
        navigationItem.rightBarButtonItems = active.navigationItem.rightBarButtonItems
    }
}
