// extra-sources: WebShellRules NotificationModels
import Foundation

/// NotificationModels needs ChatKind (ChatFormatting.swift imports UIKit), same stub as WorkApprovalChecks.
enum ChatKind: Equatable, Sendable { case duty, work, group }

/// Offline checks for the WebView app shell rules (origin, links, file names, bridge messages, session end).
@main
struct WebShellChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        let web = "https://lvt.vscgroup.io.vn"

        // Only the web app's origin talks to the bridge.
        check(WebShellRules.origin(web) == "https://lvt.vscgroup.io.vn", "Origin")
        check(WebShellRules.origin("https://Sandbox.Example:8443/x") == "https://sandbox.example:8443", "Origin with port")
        check(WebShellRules.origin("http://lvt.vscgroup.io.vn") == nil, "http refused")
        check(WebShellRules.origin(scheme: "https", host: "LVT.vscgroup.io.vn", port: 443) == "https://lvt.vscgroup.io.vn", "Default port dropped")
        check(WebShellRules.origin(scheme: "https", host: "lvt.vscgroup.io.vn", port: 0) == "https://lvt.vscgroup.io.vn", "No port")

        // Web app pages stay in the WebView; everything else leaves.
        check(WebShellRules.isWebAppURL(URL(string: "https://lvt.vscgroup.io.vn/cong-viec?x=1#a")!, webURL: web), "Own page")
        check(!WebShellRules.isWebAppURL(URL(string: "https://lvt.vscgroup.io.vn.evil.com/")!, webURL: web), "Look-alike host")
        check(!WebShellRules.isWebAppURL(URL(string: "http://lvt.vscgroup.io.vn/")!, webURL: web), "http")
        check(!WebShellRules.isWebAppURL(URL(string: "https://www.youtube.com/")!, webURL: web), "Other site")
        check(WebShellRules.isExternalLink(URL(string: "mailto:a@b.vn")!), "mailto opens outside")
        check(!WebShellRules.isExternalLink(URL(string: "file:///etc/hosts")!), "file never")
        check(!WebShellRules.isExternalLink(URL(string: "javascript:alert(1)")!), "javascript never")

        // Files handed over by the web.
        check(WebShellRules.safeFileName("../../bao-cao.pdf") == "bao-cao.pdf", "No path")
        check(WebShellRules.safeFileName("Công văn:1?.docx") == "Công văn_1_.docx", "Reserved characters")
        check(WebShellRules.safeFileName("...") == "tai-lieu", "Fallback name")

        // Bridge messages.
        func object(_ text: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        }
        let open = object(WebShellRules.notificationMessage(
            NotificationDestination(kind: "people", sourceType: "staff_fault", sourceId: "f1", notificationKey: "people:staff_fault:f1", menu: "staff-faults")
        ))
        let item = open["item"] as? [String: Any] ?? [:]
        check(open["type"] as? String == "open-notification" && item["key"] as? String == "people:staff_fault:f1" && item["menu"] as? String == "staff-faults", "Notification message")
        let handoff = object(WebShellRules.handoffMessage(id: 7, code: "abc"))
        check(handoff["id"] as? Int == 7 && handoff["code"] as? String == "abc", "Handoff message")
        check(object(WebShellRules.handoffFailedMessage(id: 7, retry: true))["retry"] as? Bool == true, "Retry flag")
        check(object(WebShellRules.handoffFailedMessage(id: 7, retry: false))["retry"] as? Bool == false, "Signed out")
        check(WebShellRules.deliverScript(#"{"type":"sign-out"}"#) == #"window.__lvtAppDeliver && window.__lvtAppDeliver({"type":"sign-out"});"#, "Deliver script")

        // Only an ended session signs the app out; network trouble never does.
        check(WebShellRules.isSessionEnded(ConvexException(code: "UNAUTHENTICATED", message: "UNAUTHENTICATED")), "Unauthenticated")
        check(WebShellRules.isSessionEnded(ConvexException(code: "CONVEX_ERROR", message: "Uncaught Error: ACCOUNT_LOCKED")), "Locked")
        check(!WebShellRules.isSessionEnded(URLError(.notConnectedToInternet)), "Offline")
        check(!WebShellRules.isSessionEnded(ConvexException(code: "HTTP_502", message: "Máy chủ lỗi 502")), "Server error")

        print("WebShellChecks: \(checks) checks passed")
    }
}
