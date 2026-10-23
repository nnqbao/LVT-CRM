package lvt.crm.data.auth

import org.json.JSONObject

enum class MenuAccess(val wireValue: String) {
    Hidden("hidden"),
    View("view"),
    ViewAll("view_all"),
    Supervisor("supervisor");

    companion object {
        fun decode(value: String?): MenuAccess = when (value) {
            "view", "edit" -> View
            "view_all" -> ViewAll
            "supervisor" -> Supervisor
            else -> Hidden
        }
    }
}

/**
 * Session for navigation. Admin/Mod use the same staff menus as normal users in the app.
 */
data class UserSession(
    val userId: String,
    val email: String,
    val name: String,
    val role: String,
    val status: String,
    val mustChangePassword: Boolean = false,
    val departmentName: String? = null,
    val positionName: String? = null,
    val positionLevel: Int? = null,
    val hasAvatar: Boolean = false,
    val avatarVersion: String? = null,
    val menuAccess: Map<String, MenuAccess> = emptyMap(),
) {
    val isOperationalManager: Boolean
        get() = role == "admin" || role == "moderator"

    private val canUseApp: Boolean
        get() = status == "active" && !mustChangePassword

    /** Giám thị (`supervisor`) is no longer valid on homeroom: the server resolves it to hidden, and so do we. */
    val homeroomAccess: MenuAccess
        get() = (menuAccess["homeroom"] ?: MenuAccess.Hidden).takeIf { it != MenuAccess.Supervisor } ?: MenuAccess.Hidden

    /** Menu `attendance` (Điểm danh) only knows hidden / supervisor for ordinary users. */
    val attendanceAccess: MenuAccess
        get() = if (menuAccess["attendance"] == MenuAccess.Supervisor) MenuAccess.Supervisor else MenuAccess.Hidden

    val workAccess: MenuAccess
        get() = (menuAccess["work"] ?: MenuAccess.Hidden).takeIf { it != MenuAccess.Supervisor } ?: MenuAccess.Hidden

    val canSeeHomeroom: Boolean
        get() = canUseApp && (isOperationalManager || homeroomAccess != MenuAccess.Hidden)

    /** Giám thị of the Điểm danh menu (never an operational manager; those see it by role). */
    val isAttendanceSupervisor: Boolean
        get() = !isOperationalManager && attendanceAccess == MenuAccess.Supervisor

    val canSeeAttendance: Boolean
        get() = canUseApp && (isOperationalManager || isAttendanceSupervisor)

    /** Báo cáo level; `supervisor` is only meaningful on homeroom, so it counts as hidden here. */
    val reportsAccess: MenuAccess
        get() = (menuAccess["reports"] ?: MenuAccess.Hidden).takeIf { it != MenuAccess.Supervisor } ?: MenuAccess.Hidden

    /** Bán trú level; the server fills `boarding` from Báo cáo for groups saved before the row existed. */
    val boardingAccess: MenuAccess
        get() = (menuAccess["boarding"] ?: MenuAccess.Hidden).takeIf { it != MenuAccess.Supervisor } ?: MenuAccess.Hidden

    /** Bán trú follows its own menu row (`menuAccess.boarding`); convex/boarding.ts re-checks every call. */
    val canSeeBoarding: Boolean
        get() = canUseApp && (isOperationalManager || boardingAccess != MenuAccess.Hidden)

    /** Kỳ bán trú management (`boarding:write`) is for operational managers only. */
    val canManageBoarding: Boolean
        get() = canUseApp && isOperationalManager

    /** Work documents/tasks. "Việc của tôi" stays available to every active account regardless. */
    val canSeeWork: Boolean
        get() = canUseApp && (isOperationalManager || workAccess != MenuAccess.Hidden)
}

internal fun decodeUserSession(result: JSONObject): UserSession? {
    val user = result.optJSONObject("user") ?: return null
    if (user.length() == 0) return null
    val rawMenu = result.optJSONObject("menuAccess")
    val menu = buildMap {
        if (rawMenu != null) {
            val keys = rawMenu.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, MenuAccess.decode(rawMenu.optString(key).takeIf { it.isNotBlank() }))
            }
        }
    }
    return UserSession(
        userId = user.optString("_id"),
        email = user.optString("email"),
        name = user.optString("name").ifBlank { user.optString("email") },
        role = user.optString("role", "user"),
        status = user.optString("status", "active"),
        mustChangePassword = user.optBoolean("mustChangePassword", false),
        departmentName = result.optJSONObject("department")?.optString("name"),
        positionName = result.optJSONObject("position")?.optString("name"),
        positionLevel = result.optJSONObject("position")?.optInt("level"),
        hasAvatar = user.optBoolean("hasAvatar", false),
        avatarVersion = user.optString("avatarVersion").takeIf { it.isNotBlank() },
        menuAccess = menu,
    )
}

sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val session: UserSession) : AuthState
    data class MustChangePassword(val session: UserSession) : AuthState
}
