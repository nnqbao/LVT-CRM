import Foundation

/// 4.0 (branch feat/ios-webview-shell only): after the native sign-in the app shows the web app
/// (WebAppViewController). false = the former native screens.
enum AppFeatures {
    static let webShell = true
}

/// App Review demo mode (Guideline 2.1 "demonstration mode", stated in the App Review notes): signing in with a
/// demo account uses the demo environment (the sandbox: same app and web code, fictional sample data) so reviewers
/// never see a school's real data. Every other account uses the real backend. The choice is made at password sign-in
/// and kept for Face ID / passkey sign-in on that device (their keys live in the environment that created them).
enum DemoEnvironment {
    static let demoEmails: Set<String> = ["admin@example.school"]
    private static let key = "lvt.demoEnvironment.active"

    static var isActive: Bool { UserDefaults.standard.bool(forKey: key) }

    static func isDemoAccount(_ email: String) -> Bool {
        demoEmails.contains(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func setActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: key)
    }

    static var convexURL: String { infoValue("LVTDemoConvexURL") ?? "https://decisive-puma-318.convex.cloud" }
    static var webURL: String { infoValue("LVTDemoWebURL") ?? "https://sandbox.thcslevantam.ai.vn" }

    private static func infoValue(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum ConvexConfig {
    /// The web app (also what the signed-in app shows). Override like `url` for a sandbox test build.
    static var webURL: String {
        if DemoEnvironment.isActive { return DemoEnvironment.webURL }
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
        if DemoEnvironment.isActive { return DemoEnvironment.convexURL }
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
