package lvt.crm.data.attendance

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.homeroom.SchoolDay
import lvt.crm.data.homeroom.isVietnamDate
import org.json.JSONArray
import org.json.JSONObject

/**
 * Điểm danh (Giám thị): whole-school roster per day and per-class save.
 * The server (convex/supervisorAttendance.ts) re-checks the actor and the date on every call:
 * Giám thị only today, admin/mod any past day of the school year, never the future.
 */
data class AttendanceYear(val id: String, val name: String, val startDate: String, val endDate: String)

data class AttendanceSaved(
    val savedAt: Long,
    val savedByName: String,
    val source: String,
    val presentCount: Int,
    val absentCount: Int,
)

data class AttendanceStudent(
    val studentId: String,
    val fullName: String,
    val rosterNumber: Int?,
    val absent: Boolean,
)

data class AttendanceClass(
    val classId: String,
    val code: String,
    val name: String,
    val gradeLevel: Int,
    val saved: AttendanceSaved?,
    val students: List<AttendanceStudent>,
) {
    val absentIds: Set<String> get() = students.filter { it.absent }.mapTo(linkedSetOf()) { it.studentId }
}

data class AttendanceGrade(val gradeLevel: Int, val classes: List<AttendanceClass>) {
    val savedCount: Int get() = classes.count { it.saved != null }
}

data class AttendanceRoster(
    val date: String,
    val today: String,
    val canChooseDate: Boolean,
    val schoolYear: AttendanceYear?,
    val schoolDay: SchoolDay,
    val grades: List<AttendanceGrade>,
) {
    fun grade(level: Int): AttendanceGrade = grades.firstOrNull { it.gradeLevel == level } ?: AttendanceGrade(level, emptyList())
    fun findClass(classId: String): AttendanceClass? = grades.asSequence().flatMap { it.classes }.firstOrNull { it.classId == classId }
}

data class AttendanceSaveResult(
    val classId: String,
    val savedAt: Long,
    val presentCount: Int,
    val absentCount: Int,
    val changedCount: Int,
)

interface AttendanceOperations {
    suspend fun roster(date: String?): AttendanceRoster
    suspend fun saveClass(date: String, classId: String, absentStudentIds: Set<String>): AttendanceSaveResult
}

class AttendanceRepository(
    private val query: suspend (String, JSONObject) -> JSONObject,
    private val mutation: suspend (String, JSONObject) -> JSONObject,
) : AttendanceOperations {
    constructor(convex: ConvexHttpClient) : this({ path, args -> convex.query(path, args) }, { path, args -> convex.mutation(path, args) })

    override suspend fun roster(date: String?): AttendanceRoster {
        val args = JSONObject()
        if (date != null) {
            require(isVietnamDate(date)) { "INVALID_DATE" }
            args.put("date", date)
        }
        val roster = decodeAttendanceRoster(query("supervisorAttendance:roster", args))
        require(date == null || roster.date == date) { "INVALID_RESPONSE_CONTEXT" }
        return roster
    }

    override suspend fun saveClass(date: String, classId: String, absentStudentIds: Set<String>): AttendanceSaveResult {
        require(isVietnamDate(date) && classId.isNotBlank()) { "INVALID_CONTEXT" }
        require(absentStudentIds.size <= ATTENDANCE_MAX_ABSENT) { "ATTENDANCE_TOO_MANY_ABSENT" }
        val args = JSONObject()
            .put("date", date)
            .put("classId", classId)
            .put("absentStudentIds", JSONArray(absentStudentIds.sorted()))
        val result = decodeAttendanceSaveResult(mutation("supervisorAttendance:saveClass", args))
        require(result.classId == classId && result.absentCount == absentStudentIds.size) { "INVALID_MUTATION_ACK" }
        return result
    }

    companion object {
        /** Mirrors SUPERVISOR_SAVE_MAX_ABSENT on the server. */
        const val ATTENDANCE_MAX_ABSENT = 200
    }
}

internal fun decodeAttendanceRoster(value: JSONObject): AttendanceRoster {
    val date = value.getString("date")
    val today = value.getString("today")
    require(isVietnamDate(date) && isVietnamDate(today)) { "INVALID_RESPONSE: date" }
    val year = if (value.isNull("schoolYear")) null else value.getJSONObject("schoolYear").let { row ->
        AttendanceYear(row.getString("_id").also { require(it.isNotBlank()) }, row.optString("name"), row.optString("startDate"), row.optString("endDate"))
    }
    val day = value.optJSONObject("schoolDay") ?: JSONObject()
    val grades = value.getJSONArray("grades").objects().map { grade ->
        val level = grade.getInt("gradeLevel")
        AttendanceGrade(level, grade.getJSONArray("classes").objects().map { decodeAttendanceClass(it) })
    }
    return AttendanceRoster(
        date = date,
        today = today,
        canChooseDate = value.optBoolean("canChooseDate", false),
        schoolYear = year,
        schoolDay = SchoolDay(day.optBoolean("isSchoolDay"), day.optString("kind"), if (day.isNull("note")) "" else day.optString("note"), day.optBoolean("outsideYear")),
        grades = grades,
    )
}

private fun decodeAttendanceClass(row: JSONObject): AttendanceClass {
    val classId = row.getString("classId")
    require(classId.isNotBlank()) { "INVALID_RESPONSE: classId" }
    val saved = if (!row.has("saved") || row.isNull("saved")) null else row.getJSONObject("saved").let { marker ->
        AttendanceSaved(
            savedAt = marker.getLong("savedAt"),
            savedByName = marker.optString("savedByName"),
            source = marker.optString("source"),
            presentCount = marker.optInt("presentCount"),
            absentCount = marker.optInt("absentCount"),
        )
    }
    val students = row.getJSONArray("students").objects().map { student ->
        val id = student.getString("studentId")
        require(id.isNotBlank()) { "INVALID_RESPONSE: studentId" }
        AttendanceStudent(
            studentId = id,
            fullName = student.optString("fullName"),
            rosterNumber = if (!student.has("rosterNumber") || student.isNull("rosterNumber")) null else student.getInt("rosterNumber"),
            absent = student.optBoolean("absent", false),
        )
    }
    require(students.map { it.studentId }.distinct().size == students.size) { "INVALID_RESPONSE: duplicate student" }
    return AttendanceClass(classId, row.optString("code"), row.optString("name"), row.optInt("gradeLevel"), saved, students)
}

internal fun decodeAttendanceSaveResult(value: JSONObject): AttendanceSaveResult {
    val classId = value.getString("classId")
    require(classId.isNotBlank()) { "INVALID_MUTATION_ACK" }
    return AttendanceSaveResult(
        classId = classId,
        savedAt = value.getLong("savedAt"),
        presentCount = value.getInt("presentCount"),
        absentCount = value.getInt("absentCount"),
        changedCount = value.optInt("changedCount"),
    )
}

/** Pure wording/state helpers for the Điểm danh screen (unit-tested). */
object AttendancePresentation {
    val gradeTabs = listOf(6, 7, 8, 9)
    private val zone: ZoneId = ZoneId.of("Asia/Ho_Chi_Minh")
    private val clock: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(zone)

    fun vietnamHm(ms: Long): String = clock.format(Instant.ofEpochMilli(ms))

    fun classStatusText(saved: AttendanceSaved?): String =
        if (saved == null) "Chưa điểm danh" else "Đã lưu ${vietnamHm(saved.savedAt)} · ${saved.absentCount} vắng"

    fun gradeTabLabel(grade: AttendanceGrade): String = "Lớp ${grade.gradeLevel} · ${grade.savedCount}/${grade.classes.size}"

    fun saveButtonLabel(className: String, absentCount: Int, saving: Boolean): String =
        if (saving) "Đang lưu…" else "Lưu lớp $className ($absentCount vắng)"

    fun countSummary(total: Int, absentCount: Int): String = "$absentCount vắng · ${total - absentCount} có mặt"

    fun savedMessage(className: String, result: AttendanceSaveResult): String =
        "Đã lưu lớp $className: ${result.absentCount} vắng, ${result.presentCount} có mặt."

    fun toggle(ids: Set<String>, id: String): Set<String> = if (id in ids) ids - id else ids + id

    /** Grades shown as tabs: Lớp 6–9 always, plus any other grade the server returns. */
    fun tabs(roster: AttendanceRoster?): List<Int> =
        (gradeTabs + roster?.grades.orEmpty().map { it.gradeLevel }).distinct().sorted()

    /** Vietnamese text for server error codes of the Điểm danh flow (mirrors web appErrorMessage). */
    fun errorMessage(raw: String?): String {
        val text = raw.orEmpty()
        val known = listOf(
            "ATTENDANCE_CAMERA_IMPORT_RETIRED" to "Nhập file điểm danh camera đã ngừng sử dụng. Giám thị điểm danh tại menu Điểm danh.",
            "ATTENDANCE_DATE_TODAY_ONLY" to "Giám thị chỉ được điểm danh cho ngày hôm nay.",
            "ATTENDANCE_DATE_IN_FUTURE" to "Không thể điểm danh cho ngày trong tương lai.",
            "ATTENDANCE_DATE_OUTSIDE_YEAR" to "Ngày điểm danh nằm ngoài thời gian của năm học.",
            "ATTENDANCE_STUDENT_NOT_IN_CLASS" to "Có học sinh không thuộc lớp này vào ngày điểm danh. Vui lòng tải lại rồi lưu lại.",
            "ATTENDANCE_TOO_MANY_ABSENT" to "Số học sinh vắng vượt quá giới hạn của một lớp.",
            "SUPERVISOR_REQUIRED" to "Chỉ Giám thị hoặc Admin/Mod mới được điểm danh.",
            "SCHOOL_YEAR_NOT_FOUND" to "Không tìm thấy năm học.",
            "CLASS_NOT_FOUND" to "Không tìm thấy lớp.",
            "CLASS_ARCHIVED" to "Lớp đã lưu trữ. Không thể điểm danh.",
            "USER_NOT_ACTIVE" to "Tài khoản không còn hoạt động. Vui lòng liên hệ quản trị viên.",
            "PASSWORD_CHANGE_REQUIRED" to "Bạn cần đổi mật khẩu trước khi tiếp tục.",
            "INVALID_MUTATION_ACK" to "Chưa xác nhận được kết quả lưu. Tải lại để kiểm tra trước khi lưu lại.",
            "INVALID_RESPONSE" to "Phản hồi máy chủ không hợp lệ. Vui lòng thử lại.",
            "INVALID_DATE" to "Ngày không hợp lệ.",
        )
        known.firstOrNull { (code, _) -> text.contains(code) }?.let { return it.second }
        if (text.contains("FORBIDDEN", ignoreCase = true)) return "Bạn không có quyền thực hiện thao tác này."
        if (text.contains("Unauthenticated", ignoreCase = true) || text.contains("UNAUTHENTICATED")) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        return "Không thể hoàn tất thao tác. Vui lòng thử lại hoặc liên hệ quản trị viên."
    }
}

private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }
