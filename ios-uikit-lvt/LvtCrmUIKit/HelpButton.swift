import SafariServices
import UIKit

extension UIViewController {
    /// Adds the "?" help button (left side, next to Back when pushed) that opens the matching guide topic.
    func installHelpButton(_ topic: HelpGuide.Topic) {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            primaryAction: UIAction { [weak self] _ in self?.openHelp(topic) }
        )
        item.accessibilityLabel = "Hướng dẫn: \(topic.label)"
        item.accessibilityHint = "Mở hướng dẫn sử dụng cho màn hình này"
        navigationItem.leftItemsSupplementBackButton = true
        let others = (navigationItem.leftBarButtonItems ?? []).filter { $0.accessibilityLabel?.hasPrefix("Hướng dẫn:") != true }
        navigationItem.leftBarButtonItems = others + [item]
    }

    func openHelp(_ topic: HelpGuide.Topic) {
        guard let url = HelpGuide.url(for: topic) else { return }
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.dismissButtonStyle = .close
        safari.modalPresentationStyle = .pageSheet
        present(safari, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}
