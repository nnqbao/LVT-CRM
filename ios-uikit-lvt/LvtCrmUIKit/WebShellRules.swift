import Foundation

/// Pure rules of the WebView app shell (offline checks in Tests/WebShellChecks.swift). The shell shows the web app
/// (`ConvexConfig.webURL`) after the native sign-in; the bridge protocol is documented in the web
/// `src/lib/appBridge.js` and mirrors the Android `ui/web/WebShellRules.kt`.
enum WebShellRules {
    /// Script message handler the web finds as `window.webkit.messageHandlers.lvtApp`.
    static let bridgeName = "lvtApp"

    /// `scheme://host[:port]` of the web app, the only origin allowed to talk to the bridge (https, or http on localhost).
    static func origin(_ webURL: String) -> String? {
        guard let components = URLComponents(string: webURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        guard scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { return nil }
        return "\(scheme)://\(host)\(components.port.map { ":\($0)" } ?? "")"
    }

    /// Origin of a security origin / URL in the same `scheme://host[:port]` form.
    static func origin(scheme: String, host: String, port: Int) -> String {
        "\(scheme.lowercased())://\(host.lowercased())\(port > 0 && port != defaultPort(scheme) ? ":\(port)" : "")"
    }

    private static func defaultPort(_ scheme: String) -> Int { scheme.lowercased() == "https" ? 443 : 80 }

    /// Pages of the web app stay in the WebView; anything else opens outside the app.
    static func isWebAppURL(_ url: URL, webURL: String) -> Bool {
        guard let expected = origin(webURL), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              scheme == "https" || scheme == "http" else { return false }
        return origin(scheme: scheme, host: host, port: url.port ?? 0) == expected
    }

    /// Links the phone may open with another app (Safari, Mail, Phone, Maps).
    static func isExternalLink(_ url: URL) -> Bool {
        ["https", "http", "mailto", "tel", "maps"].contains(url.scheme?.lowercased() ?? "")
    }

    /// A file name safe for the temporary folder (no path, control or reserved characters).
    static func safeFileName(_ name: String) -> String {
        let last = name.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? ""
        let reserved = CharacterSet(charactersIn: "<>:\"|?*").union(.controlCharacters)
        var cleaned = String(String.UnicodeScalarView(last.unicodeScalars.map { reserved.contains($0) ? "_" : $0 }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(120))
        return cleaned.isEmpty ? "tai-lieu" : cleaned
    }

    /// Message for the web: open a tapped push notification like a bell item.
    static func notificationMessage(_ destination: NotificationDestination) -> String {
        json([
            "type": "open-notification",
            "item": [
                "key": destination.notificationKey ?? "",
                "kind": destination.kind,
                "sourceType": destination.sourceType,
                "sourceId": destination.sourceId,
                "menu": destination.menu,
            ],
        ])
    }

    static func handoffMessage(id: Int, code: String) -> String {
        json(["type": "handoff", "id": id, "code": code])
    }

    /// `retry` = network trouble: the web asks again instead of signing out.
    static func handoffFailedMessage(id: Int, retry: Bool) -> String {
        json(["type": "handoff-failed", "id": id, "retry": retry])
    }

    static let signOutMessage = #"{"type":"sign-out"}"#

    /// JavaScript delivering `message` (a JSON object) to the web bridge (`window.__lvtAppDeliver`).
    static func deliverScript(_ message: String) -> String {
        "window.__lvtAppDeliver && window.__lvtAppDeliver(\(message));"
    }

    /// The app's own session is gone (signed out, revoked, locked, deactivated).
    static func isSessionEnded(_ error: Error) -> Bool {
        let text = [(error as? ConvexException)?.code, (error as? ConvexException)?.message, error.localizedDescription]
            .compactMap { $0 }
            .joined(separator: " ")
        return ["Unauthenticated", "Authentication", "UNAUTHENTICATED", "ACCOUNT_LOCKED", "USER_NOT_ACTIVE", "PASSWORD_CHANGE_REQUIRED", "NO_SESSION"]
            .contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
