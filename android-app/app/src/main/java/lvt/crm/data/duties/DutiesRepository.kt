package lvt.crm.data.duties

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import lvt.crm.data.convex.ConvexConfig
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

data class DutyDepartmentParticipants(
    val departmentName: String,
    val participantNames: List<String>,
)

data class DutyItem(
    val id: String,
    val content: String,
    val startDate: String,
    val endDate: String,
    val startTime: String,
    val endTime: String,
    val allDay: Boolean,
    val locationNames: List<String>,
    val departmentNames: List<String>,
    val departmentParticipants: List<DutyDepartmentParticipants>,
    val participantNames: List<String>,
    val myStatus: String,
    val isMine: Boolean,
    val isOngoing: Boolean,
    val isOverdue: Boolean,
    val isUpcoming: Boolean,
    val canMarkAttendance: Boolean,
    val title: String = "",
    val createdBy: String = "",
    val locationText: String = "",
    val otherParticipants: String = "",
)

data class DutiesSnapshot(
    val attendanceConfirmationEnabled: Boolean,
    val duties: List<DutyItem>,
    val canCreate: Boolean = false,
    val isAdmin: Boolean = false,
    val canViewAll: Boolean = false,
)

/** One row of the shared Lịch công tác (approved copy for teachers, working copy for văn thư/BGH). */
data class SharedDutyEvent(
    val id: String,
    val title: String,
    val content: String,
    val startDate: String,
    val endDate: String,
    val startTime: String,
    val endTime: String,
    val allDay: Boolean,
    val locationText: String,
    val departmentIds: List<String>,
    val participantUserIds: List<String>,
    val departmentNames: List<String>,
    val participantNames: List<String>,
    val otherParticipants: String,
    val canManage: Boolean,
    /** "added" | "changed" | null — only for văn thư/BGH. */
    val approvalChange: String?,
)

data class DutyWeekChange(val id: String, val kind: String, val title: String)

data class DutyWeekState(
    val weekStart: String,
    /** empty | draft | submitted | returned | approved | approved_changed */
    val status: String,
    val changeCount: Int,
    val changes: List<DutyWeekChange>,
    val missingParticipants: Int,
    val hasApprovedVersion: Boolean,
    val submittedAt: Double?,
    val submittedByName: String,
    val returnedAt: Double?,
    val returnedByName: String,
    val returnNote: String,
    val approvedAt: Double?,
    val approvedByName: String,
)

data class SharedDutyWeek(
    /** manager (văn thư) | reviewer (BGH) | public (giáo viên) */
    val viewer: String,
    val canSubmit: Boolean,
    val canReview: Boolean,
    val events: List<SharedDutyEvent>,
    val week: DutyWeekState?,
)

data class DutyFormOption(val id: String, val label: String, val detail: String = "")

data class DutyFormOptions(
    val isOps: Boolean,
    val departments: List<DutyFormOption>,
    val users: List<DutyFormOption>,
)

/** Fields `duties:update` takes; the server validates and re-checks permission. */
data class DutyDraft(
    val id: String,
    val title: String,
    val content: String,
    val startDate: String,
    val endDate: String,
    val startTime: String,
    val endTime: String,
    val allDay: Boolean,
    val locationText: String,
    val departmentIds: List<String>,
    val participantUserIds: List<String>,
    val otherParticipants: String,
)

data class SharedSchedulePdf(
    val file: File,
    val fileName: String,
)

interface DutiesOperations {
    suspend fun listMine(): DutiesSnapshot
    suspend fun setAttendance(dutyId: String, status: String)
}

class DutiesRepository(
    private val convex: ConvexHttpClient,
    private val tokenProvider: () -> String? = { null },
    cacheDir: File? = null,
    private val webUrl: String = ConvexConfig.webUrl,
) : DutiesOperations {
    private val downloadHttp = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()
    private val pdfCacheDir = cacheDir?.let { File(it, "shared-duty-pdfs") }
    override suspend fun listMine(): DutiesSnapshot {
        val result = convex.query("duties:listMine")
        val array = result.optJSONArray("duties")
        val duties = buildList {
            if (array != null) {
                for (i in 0 until array.length()) {
                    val d = array.getJSONObject(i)
                    val timing = d.optJSONObject("timing") ?: JSONObject()
                    add(
                        DutyItem(
                            id = d.optString("_id"),
                            content = d.optString("content"),
                            startDate = d.optString("startDate"),
                            endDate = d.optString("endDate"),
                            startTime = d.optString("startTime"),
                            endTime = d.optString("endTime"),
                            allDay = d.optBoolean("allDay", false),
                            locationNames = d.optJSONArray("locationNames").toStringList(),
                            departmentNames = d.optJSONArray("departmentNames").toStringList(),
                            departmentParticipants = d.optJSONArray("departmentParticipants")
                                .toDepartmentParticipants(),
                            participantNames = d.optJSONArray("participantNames").toStringList(),
                            myStatus = d.optString("myStatus", "pending"),
                            isMine = d.optBoolean("isMine", false),
                            isOngoing = timing.optBoolean("isOngoing", false),
                            isOverdue = timing.optBoolean("isOverdue", false),
                            isUpcoming = timing.optBoolean("isUpcoming", false),
                            canMarkAttendance = timing.optBoolean("canMarkAttendance", false),
                            title = d.optString("title"),
                            createdBy = d.optString("createdBy"),
                            locationText = d.optString("locationText"),
                            otherParticipants = d.optString("otherParticipants"),
                        ),
                    )
                }
            }
        }
        return DutiesSnapshot(
            attendanceConfirmationEnabled = result.optBoolean("attendanceConfirmationEnabled", false),
            duties = duties,
            canCreate = result.optBoolean("canCreate", false),
            isAdmin = result.optBoolean("isAdmin", false),
            canViewAll = result.optBoolean("canViewAll", false),
        )
    }

    override suspend fun setAttendance(dutyId: String, status: String) {
        convex.mutation(
            "duties:setAttendance",
            JSONObject()
                .put("dutyId", dutyId)
                .put("status", status),
        )
    }

    /** Monday-to-Saturday sheet plus the week's approval state. */
    suspend fun sharedWeek(weekStart: String, weekEnd: String): SharedDutyWeek {
        val result = convex.query(
            "duties:sharedSchedule",
            JSONObject().put("startDate", weekStart).put("endDate", weekEnd),
        )
        val events = buildList {
            val array = result.optJSONArray("events")
            if (array != null) {
                for (i in 0 until array.length()) {
                    val e = array.optJSONObject(i) ?: continue
                    add(
                        SharedDutyEvent(
                            id = e.optString("_id"),
                            title = e.optString("title"),
                            content = e.optString("content"),
                            startDate = e.optString("startDate"),
                            endDate = e.optString("endDate"),
                            startTime = e.optString("startTime"),
                            endTime = e.optString("endTime"),
                            allDay = e.optBoolean("allDay", false),
                            locationText = e.optString("locationText").ifBlank { e.optString("location") },
                            departmentIds = e.optJSONArray("departmentIds").toStringList(),
                            participantUserIds = e.optJSONArray("participantUserIds").toStringList(),
                            departmentNames = e.optJSONArray("departmentNames").toStringList(),
                            participantNames = e.optJSONArray("participantNames").toStringList(),
                            otherParticipants = e.optString("otherParticipants"),
                            canManage = e.optBoolean("canManage", false),
                            approvalChange = e.optString("approvalChange").takeIf { it == "added" || it == "changed" },
                        ),
                    )
                }
            }
        }
        val weeks = result.optJSONArray("weeks")
        val week = (0 until (weeks?.length() ?: 0))
            .mapNotNull { weeks?.optJSONObject(it) }
            .firstOrNull { it.optString("weekStart") == weekStart }
            ?.let { w ->
                val changes = w.optJSONArray("changes")
                DutyWeekState(
                    weekStart = w.optString("weekStart"),
                    status = w.optString("status", "empty"),
                    changeCount = w.optInt("changeCount", 0),
                    changes = (0 until (changes?.length() ?: 0)).mapNotNull { changes?.optJSONObject(it) }.map {
                        DutyWeekChange(it.optString("id"), it.optString("kind"), it.optString("title"))
                    },
                    missingParticipants = w.optInt("missingParticipants", 0),
                    hasApprovedVersion = w.optBoolean("hasApprovedVersion", false),
                    submittedAt = w.optNumber("submittedAt"),
                    submittedByName = w.optString("submittedByName"),
                    returnedAt = w.optNumber("returnedAt"),
                    returnedByName = w.optString("returnedByName"),
                    returnNote = w.optString("returnNote"),
                    approvedAt = w.optNumber("approvedAt"),
                    approvedByName = w.optString("approvedByName"),
                )
            }
        return SharedDutyWeek(
            viewer = result.optString("viewer", "public"),
            canSubmit = result.optBoolean("canSubmit", false),
            canReview = result.optBoolean("canReview", false),
            events = events,
            week = week,
        )
    }

    suspend fun submitWeek(weekStart: String) {
        convex.mutation("dutyWeeks:submit", JSONObject().put("weekStart", weekStart))
    }

    suspend fun approveWeek(weekStart: String, submittedAt: Double) {
        convex.mutation(
            "dutyWeeks:approve",
            JSONObject().put("weekStart", weekStart).put("submittedAt", submittedAt.toLong()),
        )
    }

    suspend fun returnWeek(weekStart: String, submittedAt: Double, note: String) {
        convex.mutation(
            "dutyWeeks:returnWeek",
            JSONObject().put("weekStart", weekStart).put("submittedAt", submittedAt.toLong()).put("note", note),
        )
    }

    suspend fun formOptions(): DutyFormOptions {
        val result = convex.query("duties:formOptions")
        fun options(key: String, label: (JSONObject) -> String, detail: (JSONObject) -> String) = buildList {
            val array = result.optJSONArray(key) ?: return@buildList
            for (i in 0 until array.length()) {
                val row = array.optJSONObject(i) ?: continue
                add(DutyFormOption(row.optString("_id"), label(row), detail(row)))
            }
        }
        return DutyFormOptions(
            isOps = result.optBoolean("isOps", false),
            departments = options("departments", { it.optString("name") }, { it.optString("code") }),
            users = options("users", { it.optString("name").ifBlank { it.optString("email") } }, { it.optString("email") }),
        )
    }

    suspend fun updateDuty(draft: DutyDraft) {
        convex.mutation(
            "duties:update",
            JSONObject()
                .put("id", draft.id)
                .put("title", draft.title)
                .put("content", draft.content)
                .put("startDate", draft.startDate)
                .put("endDate", draft.endDate)
                .put("startTime", draft.startTime)
                .put("endTime", draft.endTime)
                .put("allDay", draft.allDay)
                .put("locationText", draft.locationText)
                .put("departmentIds", org.json.JSONArray(draft.departmentIds))
                .put("participantUserIds", org.json.JSONArray(draft.participantUserIds))
                .put("otherParticipants", draft.otherParticipants),
        )
    }

    suspend fun downloadSharedSchedulePdf(mode: String, anchorIso: String): SharedSchedulePdf = withContext(Dispatchers.IO) {
        val token = tokenProvider()?.takeIf { it.isNotBlank() }
            ?: throw ConvexException("UNAUTHORIZED", "Bạn cần đăng nhập để xem lịch công tác chung.")
        val encodedMode = URLEncoder.encode(mode, Charsets.UTF_8.name())
        val encodedAnchor = URLEncoder.encode(anchorIso, Charsets.UTF_8.name())
        val url = "${webUrl.trimEnd('/')}/api/duties/shared-schedule.pdf?mode=$encodedMode&anchor=$encodedAnchor"
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        val directory = (pdfCacheDir ?: File(System.getProperty("java.io.tmpdir"), "lvt-shared-duty-pdfs")).apply { mkdirs() }
        val downloaded = File.createTempFile("lvt-lct-", ".pdf", directory)
        try {
            downloadHttp.newCall(request).execute().use { response ->
                if (response.code == 401 || response.code == 403) {
                    throw ConvexException("FORBIDDEN", "Bạn không có quyền xem lịch công tác chung.")
                }
                if (!response.isSuccessful) {
                    throw ConvexException("SHARED_SCHEDULE_FAILED", "Không tải được lịch công tác chung. Hãy thử lại.")
                }
                val body = response.body
                    ?: throw ConvexException("SHARED_SCHEDULE_FAILED", "Không tải được lịch công tác chung. Hãy thử lại.")
                body.byteStream().use { input ->
                    downloaded.outputStream().use { output -> input.copyTo(output) }
                }
                if (downloaded.length() <= 0L) {
                    throw ConvexException("SHARED_SCHEDULE_FAILED", "Không tải được lịch công tác chung. Hãy thử lại.")
                }
                val fileName = dispositionFileName(response.header("Content-Disposition"))
                    ?: "LCT.pdf"
                return@withContext SharedSchedulePdf(file = downloaded, fileName = fileName)
            }
        } catch (error: ConvexException) {
            downloaded.delete()
            throw error
        } catch (error: Exception) {
            downloaded.delete()
            throw ConvexException("SHARED_SCHEDULE_FAILED", "Không tải được lịch công tác chung. Hãy thử lại.")
        }
    }
}

private fun dispositionFileName(header: String?): String? {
    val value = header?.trim().orEmpty()
    if (value.isBlank()) return null
    val utf = Regex("filename\\*=UTF-8''([^;]+)", RegexOption.IGNORE_CASE).find(value)?.groupValues?.getOrNull(1)
    if (!utf.isNullOrBlank()) {
        return java.net.URLDecoder.decode(utf, Charsets.UTF_8.name())
    }
    val plain = Regex("filename=\"?([^\";]+)\"?", RegexOption.IGNORE_CASE).find(value)?.groupValues?.getOrNull(1)
    return plain?.trim()?.takeIf { it.isNotBlank() }
}

private fun JSONObject.optNumber(key: String): Double? =
    if (has(key) && !isNull(key)) optDouble(key).takeIf { !it.isNaN() } else null

private fun org.json.JSONArray?.toStringList(): List<String> {
    if (this == null) return emptyList()
    return buildList {
        for (i in 0 until length()) {
            optString(i)?.takeIf { it.isNotBlank() }?.let { add(it) }
        }
    }
}

private fun org.json.JSONArray?.toDepartmentParticipants(): List<DutyDepartmentParticipants> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            val row = optJSONObject(index) ?: continue
            val departmentName = row.optString("departmentName").trim()
            if (departmentName.isBlank()) continue
            add(
                DutyDepartmentParticipants(
                    departmentName = departmentName,
                    participantNames = row.optJSONArray("participantNames").toStringList(),
                ),
            )
        }
    }
}
