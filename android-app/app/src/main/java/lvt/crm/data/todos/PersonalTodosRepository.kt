package lvt.crm.data.todos

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import lvt.crm.data.convex.ConvexHttpClient
import org.json.JSONArray
import org.json.JSONObject

/**
 * "Việc của tôi": private to-dos of the signed-in account (convex/personalTodos.ts).
 * Every active user may use it regardless of the `work` menu; only the owner reads or writes a todo.
 * Times are epoch milliseconds; the UI shows them in Vietnam time (UTC+7, no DST).
 */
data class PersonalTodo(
    val id: String,
    val title: String,
    val note: String,
    val dueAt: Long?,
    val remindAt: Long?,
    val remindedAt: Long?,
    val completedAt: Long?,
    val createdAt: Long,
    val updatedAt: Long,
) {
    val done: Boolean get() = completedAt != null
}

data class PersonalTodoList(val open: List<PersonalTodo>, val completed: List<PersonalTodo>)

/** Payload for personalTodos.create / update; null clears the field. */
data class PersonalTodoInput(val title: String, val note: String?, val dueAt: Long?, val remindAt: Long?)

interface PersonalTodoOperations {
    suspend fun listMine(): PersonalTodoList
    suspend fun create(input: PersonalTodoInput): String
    suspend fun update(id: String, input: PersonalTodoInput)
    suspend fun setCompleted(id: String, done: Boolean)
    suspend fun remove(id: String)
}

class PersonalTodosRepository(
    private val query: suspend (String, JSONObject) -> JSONObject,
    private val mutation: suspend (String, JSONObject) -> JSONObject,
) : PersonalTodoOperations {
    constructor(convex: ConvexHttpClient) : this({ path, args -> convex.query(path, args) }, { path, args -> convex.mutation(path, args) })

    override suspend fun listMine(): PersonalTodoList = decodePersonalTodoList(query("personalTodos:listMine", JSONObject()))

    override suspend fun create(input: PersonalTodoInput): String {
        val id = mutation("personalTodos:create", input.toArgs()).optString("value")
        require(id.isNotBlank()) { "INVALID_MUTATION_ACK" }
        return id
    }

    override suspend fun update(id: String, input: PersonalTodoInput) {
        require(id.isNotBlank())
        mutation("personalTodos:update", input.toArgs().put("id", id))
    }

    override suspend fun setCompleted(id: String, done: Boolean) {
        require(id.isNotBlank())
        mutation("personalTodos:setCompleted", JSONObject().put("id", id).put("done", done))
    }

    override suspend fun remove(id: String) {
        require(id.isNotBlank())
        mutation("personalTodos:remove", JSONObject().put("id", id))
    }
}

internal fun PersonalTodoInput.toArgs(): JSONObject = JSONObject()
    .put("title", title)
    .put("note", note ?: JSONObject.NULL)
    .put("dueAt", dueAt ?: JSONObject.NULL)
    .put("remindAt", remindAt ?: JSONObject.NULL)

internal fun decodePersonalTodoList(value: JSONObject): PersonalTodoList = PersonalTodoList(
    open = value.getJSONArray("open").todos(),
    completed = value.getJSONArray("completed").todos(),
)

private fun JSONArray.todos(): List<PersonalTodo> = List(length()) { index ->
    val row = getJSONObject(index)
    val id = row.getString("_id")
    require(id.isNotBlank()) { "INVALID_RESPONSE: _id" }
    PersonalTodo(
        id = id,
        title = row.getString("title"),
        note = if (row.isNull("note")) "" else row.optString("note"),
        dueAt = row.optTime("dueAt"),
        remindAt = row.optTime("remindAt"),
        remindedAt = row.optTime("remindedAt"),
        completedAt = row.optTime("completedAt"),
        createdAt = row.optLong("createdAt"),
        updatedAt = row.optLong("updatedAt"),
    )
}

private fun JSONObject.optTime(key: String): Long? =
    if (!has(key) || isNull(key)) null else optDouble(key).takeIf { it.isFinite() && it > 0 }?.toLong()

/** Field errors shown under each input, plus the payload when everything is valid. */
data class PersonalTodoValidation(val errors: Map<String, String>, val input: PersonalTodoInput?) {
    val ok: Boolean get() = errors.isEmpty() && input != null
}

/** Pure rules for the "Việc của tôi" form and list (mirror web personalTodoDisplay.js). */
object PersonalTodoRules {
    const val TITLE_MAX = 200
    const val NOTE_MAX = 2000
    const val SOURCE_TYPE = "todo_reminder"
    const val KIND = "todo"
    val zone: ZoneId = ZoneId.of("Asia/Ho_Chi_Minh")
    private val moment: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm dd/MM/yyyy").withZone(zone)

    /** Push / bell items for a todo reminder open "Việc của tôi". */
    fun isTodoNotification(kind: String?, sourceType: String?): Boolean = kind == KIND || sourceType == SOURCE_TYPE

    fun formatMoment(ms: Long): String = moment.format(Instant.ofEpochMilli(ms))

    /** Vietnam wall-clock date + time → epoch ms. */
    fun vietnamMillis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(year, month, day, hour, minute).toInstant(ZoneOffset.ofHours(7)).toEpochMilli()

    fun vietnamDateTime(ms: Long): LocalDateTime = LocalDateTime.ofInstant(Instant.ofEpochMilli(ms), zone)

    fun isOverdue(todo: PersonalTodo, now: Long): Boolean = !todo.done && todo.dueAt != null && todo.dueAt < now

    /**
     * Validates the form. A reminder must be in the future when new or changed; an unchanged reminder
     * that already fired may stay (the server accepts it too).
     */
    fun validate(title: String, note: String, dueAt: Long?, remindAt: Long?, now: Long, previousRemindAt: Long? = null): PersonalTodoValidation {
        val errors = linkedMapOf<String, String>()
        val cleanTitle = title.trim()
        if (cleanTitle.isEmpty()) errors["title"] = "Vui lòng nhập tên việc."
        else if (cleanTitle.length > TITLE_MAX) errors["title"] = "Tên việc tối đa $TITLE_MAX ký tự."
        val cleanNote = note.trim()
        if (cleanNote.length > NOTE_MAX) errors["note"] = "Ghi chú tối đa $NOTE_MAX ký tự."
        if (dueAt != null && dueAt <= 0) errors["due"] = "Hạn chót không hợp lệ."
        if (remindAt != null && remindAt <= 0) errors["remind"] = "Giờ nhắc không hợp lệ."
        else if (remindAt != null && remindAt <= now && remindAt != previousRemindAt) errors["remind"] = "Giờ nhắc phải ở tương lai."
        return PersonalTodoValidation(
            errors,
            if (errors.isEmpty()) PersonalTodoInput(cleanTitle, cleanNote.ifEmpty { null }, dueAt, remindAt) else null,
        )
    }

    /** Vietnamese text for server error codes of personalTodos (mirrors web appErrorMessage). */
    fun errorMessage(raw: String?): String {
        val text = raw.orEmpty()
        val known = listOf(
            "INVALID_TODO_TITLE" to "Vui lòng nhập tên việc (tối đa 200 ký tự).",
            "INVALID_TODO_NOTE" to "Ghi chú tối đa 2000 ký tự.",
            "INVALID_TODO_TIME" to "Thời gian không hợp lệ.",
            "TODO_REMIND_IN_PAST" to "Giờ nhắc phải ở tương lai.",
            "TODO_NOT_FOUND" to "Việc này không còn tồn tại.",
            "USER_NOT_ACTIVE" to "Tài khoản không còn hoạt động. Vui lòng liên hệ quản trị viên.",
            "PASSWORD_CHANGE_REQUIRED" to "Bạn cần đổi mật khẩu trước khi tiếp tục.",
            "INVALID_MUTATION_ACK" to "Chưa xác nhận được kết quả. Tải lại danh sách để kiểm tra.",
        )
        known.firstOrNull { (code, _) -> text.contains(code) }?.let { return it.second }
        if (text.contains("Unauthenticated", ignoreCase = true)) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        return "Không thể hoàn tất thao tác. Vui lòng thử lại hoặc liên hệ quản trị viên."
    }
}
