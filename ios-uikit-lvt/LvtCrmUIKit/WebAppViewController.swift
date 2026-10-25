import Network
import QuickLook
import UIKit
import WebKit

/// The signed-in app: the web app (same menus, screens and guide videos as the browser) in a WKWebView. Native
/// parts: sign-in (password, Face ID, passkey) before this screen, push notifications, files from the web (Quick
/// Look, Save to Files), Face ID / passkey settings and the "Không có kết nối" screen.
///
/// The WebView gets its own session through a single-use code (convex/appHandoff.ts) sent over the
/// origin-restricted `lvtApp` script message handler; protocol in the web `src/lib/appBridge.js`.
@MainActor
final class WebAppViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, QLPreviewControllerDataSource {
    private let session: UserSession
    private let convex: ConvexHttpClient
    private let notificationsRepository: NotificationsRepository
    private let quickSignIn: QuickSignInService
    private let onSignOut: () -> Void
    private let webURL = ConvexConfig.webURL
    private var webView: WKWebView!
    private var webReady = false
    private var pendingOpens: [NotificationDestination] = []
    private var loadFailed = false
    private var handoffFailed = false
    private var online = true
    private let monitor = NWPathMonitor()
    private let banner = UILabel()
    private let errorView = ConnectionMessageView()
    private var previewURL: URL?

    init(
        session: UserSession,
        convex: ConvexHttpClient,
        notificationsRepository: NotificationsRepository,
        quickSignIn: QuickSignInService,
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.convex = convex
        self.notificationsRepository = notificationsRepository
        self.quickSignIn = quickSignIn
        self.onSignOut = onSignOut
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        monitor.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let configuration = WKWebViewConfiguration()
        // App-bound domains (Info.plist WKAppBoundDomains): needed for the guide's video service worker.
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.applicationNameForUserAgent = "LvtCrmApp/\(AppVersion.marketing) (iOS)"
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: WebShellRules.bridgeName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        banner.text = "Không có kết nối"
        banner.textAlignment = .center
        banner.font = .preferredFont(forTextStyle: .subheadline)
        banner.adjustsFontForContentSizeCategory = true
        banner.textColor = .white
        banner.backgroundColor = .systemRed
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        errorView.isHidden = true
        errorView.onRetry = { [weak self] in self?.retry() }
        errorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            banner.topAnchor.constraint(equalTo: guide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "vn.lvt.crm.webshell.network"))

        if let url = URL(string: webURL) { webView.load(URLRequest(url: url)) }
    }

    // MARK: Notifications

    /// A tapped notification: the app marks it read, the web opens it like a bell item.
    func route(_ destination: NotificationDestination) {
        pendingOpens.append(destination)
        if let key = destination.notificationKey {
            Task { [notificationsRepository] in try? await notificationsRepository.markRead(notificationKey: key) }
        }
        flushPendingOpens()
    }

    private func flushPendingOpens() {
        guard webReady, !pendingOpens.isEmpty else { return }
        let opens = pendingOpens
        pendingOpens.removeAll()
        opens.forEach { post(WebShellRules.notificationMessage($0)) }
    }

    // MARK: Bridge

    fileprivate func receive(_ message: WKScriptMessage) {
        // Only the web app's own top-level page may talk to the app.
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              WebShellRules.origin(scheme: origin.protocol, host: origin.host, port: origin.port) == WebShellRules.origin(webURL),
              let text = message.body as? String,
              let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "ready":
            // Never show another account's web session (left over in WebView storage).
            if let userId = json["userId"] as? String, !userId.isEmpty, userId != session.userId {
                post(WebShellRules.signOutMessage)
            } else {
                webReady = true
                handoffFailed = false
                updateChrome()
                flushPendingOpens()
                #if DEBUG
                DebugAutomation.runScriptIfRequested(in: webView)
                #endif
            }
        case "handoff-request":
            issueHandoff(id: (json["id"] as? Int) ?? 0)
        case "handoff-error":
            handoffFailed = true
            updateChrome()
        case "signed-out":
            onSignOut()
        case "quick-sign-in":
            let controller = UINavigationController(rootViewController: QuickSignInViewController(session: session, quickSignIn: quickSignIn))
            present(controller, animated: true)
        case "file":
            receiveFile(json)
        default:
            break
        }
    }

    private func post(_ message: String) {
        guard let url = webView.url, WebShellRules.isWebAppURL(url, webURL: webURL) else { return }
        webView.evaluateJavaScript(WebShellRules.deliverScript(message), completionHandler: nil)
    }

    private func issueHandoff(id: Int) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await convex.action("appHandoff:issue")
                if let code = result["code"] as? String, !code.isEmpty {
                    post(WebShellRules.handoffMessage(id: id, code: code))
                } else {
                    post(WebShellRules.handoffFailedMessage(id: id, retry: true))
                }
            } catch {
                if WebShellRules.isSessionEnded(error) {
                    post(WebShellRules.handoffFailedMessage(id: id, retry: false))
                    onSignOut()
                } else {
                    post(WebShellRules.handoffFailedMessage(id: id, retry: true))
                }
            }
        }
    }

    // MARK: Files

    /// Files the web hands over (`{ type: 'file' }`, base64): Quick Look shows them, its share button saves them.
    private func receiveFile(_ json: [String: Any]) {
        guard let base64 = json["data"] as? String,
              let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else {
            showAlert("Không mở được tệp", "Vui lòng thử lại.")
            return
        }
        let name = WebShellRules.safeFileName((json["name"] as? String) ?? "")
        do {
            let directory = WebShellStorage.filesDirectory
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            previewURL = url
            let preview = QLPreviewController()
            preview.dataSource = self
            present(preview, animated: true)
        } catch {
            showAlert("Không mở được tệp", "Vui lòng thử lại.")
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: "/dev/null")) as NSURL
    }

    // MARK: Connection

    private func networkChanged(_ isOnline: Bool) {
        let cameBack = isOnline && !online
        online = isOnline
        if cameBack, loadFailed { retry() }
        updateChrome()
    }

    private func retry() {
        loadFailed = false
        handoffFailed = false
        updateChrome()
        if webView.url == nil, let url = URL(string: webURL) {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    private func updateChrome() {
        let showError = loadFailed || handoffFailed
        errorView.isHidden = !showError
        errorView.configure(
            title: "Không có kết nối",
            message: online ? "Không kết nối được máy chủ của trường. Vui lòng thử lại." : "Hãy bật Wi-Fi hoặc dữ liệu di động rồi thử lại."
        )
        banner.isHidden = online || showError
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if WebShellRules.isWebAppURL(url, webURL: webURL) || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return decisionHandler(.allow)
        }
        // Sub-frames of other sites (none today) and links leave the app.
        if navigationAction.targetFrame?.isMainFrame != false, WebShellRules.isExternalLink(url) {
            UIApplication.shared.open(url)
        }
        decisionHandler(navigationAction.targetFrame?.isMainFrame == false ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 500 {
            loadFailed = true
            updateChrome()
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        webReady = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func failed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loadFailed = true
        updateChrome()
    }

    // MARK: WKUIDelegate (target=_blank, alert, confirm)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if WebShellRules.isWebAppURL(url, webURL: webURL) {
                webView.load(navigationAction.request)
            } else if WebShellRules.isExternalLink(url) {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default) { _ in completionHandler() })
        presentOrComplete(alert) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in completionHandler(true) })
        presentOrComplete(alert) { completionHandler(false) }
    }

    private func presentOrComplete(_ alert: UIAlertController, fallback: @escaping () -> Void) {
        guard presentedViewController == nil, view.window != nil else { return fallback() }
        present(alert, animated: true)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        if presentedViewController == nil { present(alert, animated: true) }
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle with the view controller.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WebAppViewController?

    init(_ target: WebAppViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.receive(message) }
    }
}

/// "Không có kết nối" (full screen) with Thử lại; also used when the app starts without network.
final class ConnectionMessageView: UIView {
    var onRetry: (() -> Void)?
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        icon.tintColor = .secondaryLabel
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        var button = UIButton.Configuration.filled()
        button.title = "Thử lại"
        let retry = UIButton(configuration: button, primaryAction: UIAction { [weak self] _ in self?.onRetry?() })
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, messageLabel, retry])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -16),
        ])
        configure(title: "Không có kết nối", message: "Hãy bật Wi-Fi hoặc dữ liệu di động rồi thử lại.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }
}

/// Start without network (saved sign-in kept): retries by itself when the network returns.
final class OfflineStartViewController: UIViewController {
    private let onRetry: () async -> Void
    private let monitor = NWPathMonitor()

    init(onRetry: @escaping () async -> Void) {
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        monitor.cancel()
    }

    override func loadView() {
        let messageView = ConnectionMessageView()
        messageView.configure(title: "Không có kết nối", message: "Hãy bật Wi-Fi hoặc dữ liệu di động. Ứng dụng tự mở lại khi có mạng.")
        messageView.onRetry = { [weak self] in self?.retry() }
        view = messageView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Retry only when the network comes back (the first update just reports the current state),
        // so a server that is down is not hammered in a loop.
        var wasOnline: Bool?
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            defer { wasOnline = online }
            guard online, wasOnline == false else { return }
            Task { @MainActor in self?.retry() }
        }
        monitor.start(queue: DispatchQueue(label: "vn.lvt.crm.offline.network"))
    }

    private func retry() {
        Task { await onRetry() }
    }
}

/// Signing out (or another account signing in): nothing of the web session stays on the phone.
enum WebShellStorage {
    static var filesDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("web-files", isDirectory: true)
    }

    @MainActor
    static func clear() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: {}
        )
        try? FileManager.default.removeItem(at: filesDirectory)
    }
}

#if DEBUG
/// Simulator end-to-end checks only (Debug builds; never compiled into a release): `simctl launch` with
/// SIMCTL_CHILD_LVT_TEST_EMAIL / _PASSWORD signs in once (sandbox test account), SIMCTL_CHILD_LVT_TEST_JS runs once
/// in the web app when it is ready.
@MainActor
enum DebugAutomation {
    private static var signedIn = false
    private static var ranScript = false

    static func signInIfRequested(_ authRepository: AuthRepository) {
        let env = ProcessInfo.processInfo.environment
        guard !signedIn, let email = env["LVT_TEST_EMAIL"], let password = env["LVT_TEST_PASSWORD"] else { return }
        signedIn = true
        Task { _ = await authRepository.signIn(email: email, password: password) }
    }

    static func runScriptIfRequested(in webView: WKWebView) {
        guard !ranScript, let script = ProcessInfo.processInfo.environment["LVT_TEST_JS"] else { return }
        ranScript = true
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
#endif
