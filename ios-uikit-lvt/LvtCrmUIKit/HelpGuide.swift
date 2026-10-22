import Foundation

/// "?" help: the web user guide in compact embed mode (`/huong-dan-su-dung.html?embed=1#anchor`), one topic per
/// screen. Anchors mirror the web `GUIDE_ANCHORS` (src/navigationRoutes.js); keep them in sync.
enum HelpGuide {
    static let path = "/huong-dan-su-dung.html"

    enum Topic: String, CaseIterable {
        /// Tổng quan has no web menu: the embed opens the guide's first part (Bắt đầu nhanh).
        case overview = ""
        case reports = "menu-bao-cao"
        case notifications = "tb-thong-bao"
        case chat = "td-trao-doi"
        case duties = "menu-lich-cong-tac"
        case work = "menu-cong-viec"
        case homeroom = "menu-lop-chu-nhiem"
        case attendance = "menu-diem-danh"
        case boarding = "bt-ban-tru"
        case profile = "tai-khoan-ca-nhan"
        case changePassword = "doi-mat-khau"
        case devices = "thiet-bi-dang-nhap"

        /// Spoken/visible name for the "?" button ("Hướng dẫn: Công việc").
        var label: String {
            switch self {
            case .overview: return "Tổng quan"
            case .reports: return "Báo cáo"
            case .notifications: return "Thông báo"
            case .chat: return "Trao đổi"
            case .duties: return "Lịch công tác"
            case .work: return "Công việc"
            case .homeroom: return "Lớp chủ nhiệm"
            case .attendance: return "Điểm danh"
            case .boarding: return "Bán trú"
            case .profile: return "Tài khoản cá nhân"
            case .changePassword: return "Đổi mật khẩu"
            case .devices: return "Thiết bị đăng nhập"
            }
        }
    }

    /// Public guide page (no credentials): `<web base>/huong-dan-su-dung.html?embed=1#<anchor>`.
    static func url(for topic: Topic, webBase: String = ConvexConfig.webURL) -> URL? {
        let base = webBase.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard var components = URLComponents(string: base + path),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        components.queryItems = [URLQueryItem(name: "embed", value: "1")]
        if !topic.rawValue.isEmpty { components.fragment = topic.rawValue }
        return components.url
    }
}
