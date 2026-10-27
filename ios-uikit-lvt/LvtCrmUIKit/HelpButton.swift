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
        presentWebPage(url)
    }

    /// A page of the web app (the guide, or Ghi nhận lỗi / Đánh giá nhân sự, which have no app screen),
    /// shown in Safari View Controller on top of whatever is presented.
    func presentWebPage(_ url: URL) {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.dismissButtonStyle = .close
        safari.modalPresentationStyle = .pageSheet
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        presenter.present(safari, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}
