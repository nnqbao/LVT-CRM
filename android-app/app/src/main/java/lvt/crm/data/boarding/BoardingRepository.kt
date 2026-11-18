package lvt.crm.data.boarding

import java.util.Calendar
import java.util.TimeZone
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bán trú (convex/boarding.ts). The server is the source of truth:
 * - `boarding:report` (Danh sách tham gia): admin/mod and users whose Báo cáo menu is not hidden;
 *   `view` sees their own department, `view_all` the whole school.
 * - `boarding:listAdmin/create/update/remove` (Kỳ bán trú): admin/mod only (`boarding:write`).
 */
data class BoardingPeriod(
    val id: String,
    val semester: Int,
    val schoolYear: String,
    val participantCount: Int = 0,
)

data class BoardingPerson(
    val id: String,
    val name: String,
    val email: String = "",
    val departmentName: String = "",
    val positionName: String = "",
)

data class BoardingGroup(
    val departmentName: String,
    val participants: List<BoardingPerson>,
)

data class BoardingReport(
    /** `all` (view_all / admin-mod) or `department`. */
    val visibilityScope: String,
    val periods: List<BoardingPeriod>,
    val selectedPeriod: BoardingPeriod?,
    val groups: List<BoardingGroup>,
    val totalParticipants: Int,
) {
    val isSchoolWide: Boolean get() = visibilityScope == "all"
}

data class BoardingAdminPeriod(
    val period: BoardingPeriod,
    val participantUserIds: List<String>,
    val participants: List<BoardingPerson>,
)

data class BoardingAdminData(
    val users: List<BoardingPerson>,
    val periods: List<BoardingAdminPeriod>,
)

data class BoardingPeriodInput(
    val semester: Int,
    val schoolYear: String,
    val participantUserIds: List<String>,
)

/** Labels and client-side checks shared by the screens (web `boardingLabels.js`, BoardingManagement). */
object BoardingRules {
    /** "Học kỳ 1 · Năm học 2026-2027"; [short] drops the year: "Học kỳ 1". */
    fun periodLabel(semester: Int, schoolYear: String, short: Boolean = false): String {
        val term = "Học kỳ $semester"
        return if (short || schoolYear.isBlank()) term else "$term · Năm học $schoolYear"
    }

    fun periodLabel(period: BoardingPeriod?, short: Boolean = false): String =
        period?.let { periodLabel(it.semester, it.schoolYear, short) } ?: "Chưa có kỳ bán trú"

    /** School year that contains [nowMillis] (a school year starts in July, as on the web). */
    fun currentSchoolYear(nowMillis: Long = System.currentTimeMillis()): String {
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("GMT+07:00"))
        calendar.timeInMillis = nowMillis
        val year = calendar.get(Calendar.YEAR)
        val base = if (calendar.get(Calendar.MONTH) >= Calendar.JULY) year else year - 1
        return "$base-${base + 1}"
    }

    /** Seven options: two years back to four years ahead of the current school year (web parity). */
    fun schoolYearOptions(nowMillis: Long = System.currentTimeMillis(), include: String? = null): List<String> {
        val base = currentSchoolYear(nowMillis).substringBefore('-').toInt()
        val options = (0 until 7).map { index -> "${base - 2 + index}-${base - 1 + index}" }.toMutableList()
        if (!include.isNullOrBlank() && include !in options) {
            options += include
            options.sort()
        }
        return options
    }

    private val schoolYearRe = Regex("""^(\d{4})-(\d{4})$""")

    /** Same checks as the server's cleanInput; returns the web message or null. */
    fun validate(input: BoardingPeriodInput): String? {
        if (input.semester != 1 && input.semester != 2) return BoardingErrorMessages.messages.getValue("INVALID_SEMESTER")
        val match = schoolYearRe.matchEntire(input.schoolYear.trim())
        if (match == null || match.groupValues[2].toInt() != match.groupValues[1].toInt() + 1) {
            return BoardingErrorMessages.messages.getValue("INVALID_SCHOOL_YEAR")
        }
        if (input.participantUserIds.none { it.isNotBlank() }) {
            return BoardingErrorMessages.messages.getValue("BOARDING_TEACHERS_REQUIRED")
        }
        return null
    }

    fun hasPeriodForYear(periods: List<BoardingPeriod>, schoolYear: String): Boolean =
        periods.any { it.schoolYear == schoolYear }
}

/** Web BoardingManagement errorMessage(); unknown failures use [FALLBACK]. */
object BoardingErrorMessages {
    const val FALLBACK = "Không thể hoàn tất thao tác. Vui lòng thử lại."

    val messages: Map<String, String> = linkedMapOf(
        "INVALID_SEMESTER" to "Học kỳ chỉ được chọn 1 hoặc 2.",
        "INVALID_SCHOOL_YEAR" to "Năm học không hợp lệ.",
        "BOARDING_TEACHERS_REQUIRED" to "Vui lòng chọn ít nhất một giáo viên.",
        "INVALID_BOARDING_TEACHER" to "Có giáo viên không hợp lệ hoặc đã ngưng hoạt động.",
        "BOARDING_PERIOD_EXISTS" to "Kỳ bán trú này đã tồn tại.",
        "BOARDING_PERIOD_NOT_FOUND" to "Không tìm thấy kỳ bán trú.",
        "BOARDING_PERIOD_FORBIDDEN" to "Bạn không có quyền xem kỳ bán trú này.",
    )

    private val codesByLength = messages.keys.sortedByDescending { it.length }

    fun codeIn(raw: String): String? = codesByLength.firstOrNull { raw.contains(it) }

    fun messageFor(raw: String): String? = codeIn(raw)?.let(messages::get)

    private fun rawOf(error: Throwable): String = when (error) {
        is ConvexException -> "${error.code} ${error.message.orEmpty()}"
        else -> error.message.orEmpty()
    }

    fun hasCode(error: Throwable, code: String): Boolean = rawOf(error).contains(code)

    fun messageFor(error: Throwable, fallback: String = FALLBACK): String {
        val raw = rawOf(error)
        messageFor(raw)?.let { return it }
        if (raw.contains("FORBIDDEN") || raw.contains("NOT_OPERATIONAL_MANAGER") || raw.contains("ADMIN_REQUIRED")) {
            return "Bạn không có quyền thực hiện thao tác này."
        }
        return fallback
    }
}

interface BoardingOperations {
    suspend fun report(periodId: String? = null): BoardingReport
    suspend fun listAdmin(): BoardingAdminData
    suspend fun create(input: BoardingPeriodInput): String
    suspend fun update(id: String, input: BoardingPeriodInput)
    suspend fun remove(id: String)
}

class BoardingRepository(private val convex: ConvexHttpClient) : BoardingOperations {
    override suspend fun report(periodId: String?): BoardingReport {
        val args = JSONObject()
        if (!periodId.isNullOrBlank()) args.put("periodId", periodId)
        return decodeBoardingReport(convex.query("boarding:report", args))
    }

    override suspend fun listAdmin(): BoardingAdminData = decodeBoardingAdmin(convex.query("boarding:listAdmin"))

    override suspend fun create(input: BoardingPeriodInput): String {
        val result = convex.mutation("boarding:create", input.toArgs())
        return result.optString("value")
    }

    override suspend fun update(id: String, input: BoardingPeriodInput) {
        convex.mutation("boarding:update", input.toArgs().put("id", id))
    }

    override suspend fun remove(id: String) {
        convex.mutation("boarding:remove", JSONObject().put("id", id))
    }

    private fun BoardingPeriodInput.toArgs(): JSONObject = JSONObject()
        .put("semester", semester)
        .put("schoolYear", schoolYear.trim())
        .put("participantUserIds", JSONArray(participantUserIds.map { it.trim() }.filter { it.isNotEmpty() }.distinct()))
}

internal fun decodeBoardingReport(json: JSONObject): BoardingReport {
    val groupsJson = json.optJSONArray("groups") ?: JSONArray()
    val groups = List(groupsJson.length()) { index ->
        val group = groupsJson.getJSONObject(index)
        BoardingGroup(
            departmentName = group.optString("departmentName").ifBlank { "Chưa gán phòng ban" },
            participants = decodePeople(group.optJSONArray("participants")),
        )
    }
    return BoardingReport(
        visibilityScope = json.optString("visibilityScope", "department"),
        periods = decodePeriods(json.optJSONArray("periods")),
        selectedPeriod = json.optJSONObject("selectedPeriod")?.let(::decodePeriod),
        groups = groups,
        totalParticipants = json.optInt("totalParticipants", groups.sumOf { it.participants.size }),
    )
}

internal fun decodeBoardingAdmin(json: JSONObject): BoardingAdminData {
    val periodsJson = json.optJSONArray("periods") ?: JSONArray()
    val periods = List(periodsJson.length()) { index ->
        val item = periodsJson.getJSONObject(index)
        val ids = item.optJSONArray("participantUserIds") ?: JSONArray()
        val participantIds = List(ids.length()) { ids.optString(it) }.filter { it.isNotBlank() }
        BoardingAdminPeriod(
            period = decodePeriod(item).copy(participantCount = participantIds.size),
            participantUserIds = participantIds,
            participants = decodePeople(item.optJSONArray("participants")),
        )
    }.filter { it.period.id.isNotBlank() }
    return BoardingAdminData(users = decodePeople(json.optJSONArray("users")), periods = periods)
}

private fun decodePeriods(items: JSONArray?): List<BoardingPeriod> {
    if (items == null) return emptyList()
    return List(items.length()) { decodePeriod(items.getJSONObject(it)) }.filter { it.id.isNotBlank() }
}

private fun decodePeriod(item: JSONObject) = BoardingPeriod(
    id = item.optString("_id"),
    semester = item.optInt("semester", 1),
    schoolYear = item.optString("schoolYear"),
    participantCount = item.optInt("participantCount", 0),
)

private fun decodePeople(items: JSONArray?): List<BoardingPerson> {
    if (items == null) return emptyList()
    return List(items.length()) { index ->
        val item = items.optJSONObject(index) ?: return@List null
        BoardingPerson(
            id = item.optString("_id"),
            name = item.optString("name").ifBlank { item.optString("email") }.ifBlank { "Chưa đặt tên" },
            email = item.optString("email"),
            departmentName = item.optString("departmentName"),
            positionName = item.optString("positionName"),
        )
    }.filterNotNull().filter { it.id.isNotBlank() }
}
