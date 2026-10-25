import Foundation

enum MenuAccess: String, Equatable, Sendable {
    case hidden
    case view
    case viewAll = "view_all"
    case supervisor

    static func decode(_ value: Any?) -> MenuAccess {
        guard let raw = value as? String else { return .hidden }
        if raw == "edit" { return .view }
        return MenuAccess(rawValue: raw) ?? .hidden
    }

    /// Mirrors `effectiveMenuAccessLevel` (convex/menuAccess.ts): Giám thị (`supervisor`) is valid only on
    /// the `attendance` menu, and that menu accepts only `hidden` or `supervisor`. Anything else is hidden.
    static func decode(_ value: Any?, menu: String) -> MenuAccess {
        let access = decode(value)
        if menu == attendanceMenu { return access == .supervisor ? .supervisor : .hidden }
        return access == .supervisor ? .hidden : access
    }

    static let attendanceMenu = "attendance"
}

struct UserSession: Equatable, Sendable {
    let userId: String
    let email: String
    let name: String
    let role: String
    let status: String
    let mustChangePassword: Bool
    let departmentName: String?
    let positionName: String?
    let positionLevel: Int?
    let hasAvatar: Bool
    let avatarVersion: String?
    let menuAccess: [String: MenuAccess]

    var isOperationalManager: Bool {
        role == "admin" || role == "moderator"
    }

    /// Active account without a pending mandatory password change.
    var canWork: Bool { status == "active" && !mustChangePassword }

    var homeroomAccess: MenuAccess { menuAccess["homeroom"] ?? .hidden }
    var canSeeHomeroom: Bool {
        canWork && (isOperationalManager || homeroomAccess != .hidden)
    }

    /// Điểm danh menu: Giám thị (`attendance` = `supervisor`) or admin/mod. The backend re-checks every call.
    var attendanceAccess: MenuAccess { menuAccess[MenuAccess.attendanceMenu] ?? .hidden }
    var isAttendanceSupervisor: Bool { !isOperationalManager && attendanceAccess == .supervisor }
    var canSeeAttendance: Bool { canWork && (isOperationalManager || attendanceAccess == .supervisor) }

    /// Web WorkHub `workHidden`: ordinary users whose `work` menu is hidden see only "Việc của tôi".
    var isWorkMenuHidden: Bool { !isOperationalManager && (menuAccess["work"] ?? .hidden) == .hidden }

    var roleLabel: String {
        switch role {
        case "admin": return "Quản trị viên"
        case "moderator": return "Điều phối viên"
        default: return "Nhân sự"
        }
    }
}

extension UserSession {
    init?(sessionContext result: [String: Any]) {
        guard let user = result["user"] as? [String: Any], !user.isEmpty else { return nil }
        let department = result["department"] as? [String: Any]
        let position = result["position"] as? [String: Any]
        let email = (user["email"] as? String) ?? ""
        let rawMenuAccess = result["menuAccess"] as? [String: Any] ?? [:]
        let menuAccess = rawMenuAccess.reduce(into: [String: MenuAccess]()) { result, entry in
            result[entry.key] = MenuAccess.decode(entry.value, menu: entry.key)
        }
        let rawName = (user["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            userId: (user["_id"] as? String) ?? "",
            email: email,
            name: rawName.isEmpty ? email : rawName,
            role: (user["role"] as? String) ?? "user",
            status: (user["status"] as? String) ?? "active",
            mustChangePassword: (user["mustChangePassword"] as? Bool) ?? false,
            departmentName: department?["name"] as? String,
            positionName: position?["name"] as? String,
            positionLevel: position?["level"] as? Int,
            hasAvatar: (user["hasAvatar"] as? Bool) ?? false,
            avatarVersion: user["avatarVersion"] as? String,
            menuAccess: menuAccess
        )
    }
}

enum AuthState: Equatable, Sendable {
    case loading
    case signedOut
    /// Saved sign-in kept, but the server could not be reached at start: "Không có kết nối" + Thử lại.
    case offline
    case signedIn(UserSession)
    case mustChangePassword(UserSession)

    var isAuthenticated: Bool {
        switch self {
        case .signedIn, .mustChangePassword: return true
        default: return false
        }
    }

    var session: UserSession? {
        switch self {
        case .signedIn(let session), .mustChangePassword(let session): return session
        default: return nil
        }
    }
}
