import Foundation

/// 4.0 (branch feat/ios-webview-shell only): after the native sign-in the app shows the web app
/// (WebAppViewController). false = the former native screens.
enum AppFeatures {
    static let webShell = true
}

enum ConvexConfig {
    /// The web app (also what the signed-in app shows). Override like `url` for a sandbox test build.
    static var webURL: String {
        if let override = Bundle.main.object(forInfoDictionaryKey: "LVTWebURL") as? String,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #if DEBUG
        return ProcessInfo.processInfo.environment["LVT_WEB_URL"] ?? "https://lvt.vscgroup.io.vn"
        #else
        return "https://lvt.vscgroup.io.vn"
        #endif
    }

    static var url: String {
        if let override = Bundle.main.object(forInfoDictionaryKey: "LVTConvexURL") as? String,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #if DEBUG
        return ProcessInfo.processInfo.environment["LVT_CONVEX_URL"]
            ?? "https://confident-guanaco-953.convex.cloud"
        #else
        return "https://confident-guanaco-953.convex.cloud"
        #endif
    }

    static var appId: String {
        Bundle.main.bundleIdentifier ?? "vn.lvt.crm"
    }
}
