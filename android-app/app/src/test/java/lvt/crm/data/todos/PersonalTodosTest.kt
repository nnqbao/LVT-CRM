package lvt.crm.data.todos

import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PersonalTodosTest {
    private val now = 1792629600000L // 2026-10-22 07:40 (UTC+7)

    @Test fun `listMine decodes open and completed rows with nullable times`() {
        val list = decodePersonalTodoList(JSONObject("""{"open":[
            {"_id":"t1","title":"Nộp giáo án","note":"","dueAt":1792666800000,"remindAt":null,"remindedAt":null,"completedAt":null,"createdAt":1,"updatedAt":2},
            {"_id":"t2","title":"Gọi phụ huynh","note":"Lớp 6-1","dueAt":null,"remindAt":1792630000000,"remindedAt":null,"completedAt":null,"createdAt":1,"updatedAt":2}],
            "completed":[{"_id":"t3","title":"Họp tổ","note":"","dueAt":null,"remindAt":null,"remindedAt":null,"completedAt":1792600000000,"createdAt":1,"updatedAt":2}]}"""))
        assertEquals(listOf("t1", "t2"), list.open.map { it.id })
        assertEquals(1792666800000, list.open[0].dueAt)
        assertNull(list.open[0].remindAt)
        assertEquals("Lớp 6-1", list.open[1].note)
        assertTrue(list.completed.single().done)
        assertFalse(list.open[0].done)
        assertTrue(runCatching { decodePersonalTodoList(JSONObject("{}")) }.isFailure)
        assertTrue(runCatching { decodePersonalTodoList(JSONObject("""{"open":[{"_id":"","title":"x"}],"completed":[]}""")) }.isFailure)
    }

    @Test fun `create update complete remove send the exact owner-only payloads`() = runTest {
        val calls = mutableListOf<Pair<String, JSONObject>>()
        val repository = PersonalTodosRepository(
            { _, _ -> JSONObject("""{"open":[],"completed":[]}""") },
            { path, args -> calls += path to args; if (path == "personalTodos:create") JSONObject().put("value", "new-id") else JSONObject() },
        )
        assertEquals("new-id", repository.create(PersonalTodoInput("A", null, 10L, null)))
        repository.update("t1", PersonalTodoInput("B", "ghi chú", null, 20L))
        repository.setCompleted("t1", true)
        repository.remove("t1")
        assertEquals(listOf("personalTodos:create", "personalTodos:update", "personalTodos:setCompleted", "personalTodos:remove"), calls.map { it.first })
        val create = calls[0].second
        assertEquals(setOf("title", "note", "dueAt", "remindAt"), create.keys().asSequence().toSet())
        assertTrue(create.isNull("note")); assertTrue(create.isNull("remindAt")); assertEquals(10L, create.getLong("dueAt"))
        assertEquals("t1", calls[1].second.getString("id")); assertTrue(calls[1].second.isNull("dueAt"))
        assertEquals(true, calls[2].second.getBoolean("done"))
        assertEquals(setOf("id"), calls[3].second.keys().asSequence().toSet())
        val noId = PersonalTodosRepository({ _, _ -> JSONObject() }, { _, _ -> JSONObject() })
        assertTrue(runCatching { noId.create(PersonalTodoInput("A", null, null, null)) }.isFailure)
    }

    @Test fun `validation mirrors the server rules`() {
        val empty = PersonalTodoRules.validate("  ", "", null, null, now)
        assertFalse(empty.ok); assertEquals("Vui lòng nhập tên việc.", empty.errors["title"])
        assertEquals("Tên việc tối đa 200 ký tự.", PersonalTodoRules.validate("x".repeat(201), "", null, null, now).errors["title"])
        assertEquals("Ghi chú tối đa 2000 ký tự.", PersonalTodoRules.validate("A", "x".repeat(2001), null, null, now).errors["note"])
        assertEquals("Giờ nhắc phải ở tương lai.", PersonalTodoRules.validate("A", "", null, now - 60_000, now).errors["remind"])
        // An unchanged reminder that already fired may stay.
        assertTrue(PersonalTodoRules.validate("A", "", null, now - 60_000, now, previousRemindAt = now - 60_000).ok)
        // A past due date is allowed (it just shows "Quá hạn").
        val ok = PersonalTodoRules.validate("  Soạn bài ", "  ", now - 1, now + 60_000, now)
        assertTrue(ok.ok)
        assertEquals(PersonalTodoInput("Soạn bài", null, now - 1, now + 60_000), ok.input)
    }

    @Test fun `Vietnam wall clock formatting overdue and notification routing`() {
        assertEquals("07:40 22/10/2026", PersonalTodoRules.formatMoment(now))
        assertEquals(now, PersonalTodoRules.vietnamMillis(2026, 10, 22, 7, 40))
        assertEquals(7, PersonalTodoRules.vietnamDateTime(now).hour)
        val todo = PersonalTodo("t", "A", "", now - 1, null, null, null, 0, 0)
        assertTrue(PersonalTodoRules.isOverdue(todo, now))
        assertFalse(PersonalTodoRules.isOverdue(todo.copy(completedAt = now), now))
        assertFalse(PersonalTodoRules.isOverdue(todo.copy(dueAt = null), now))
        assertTrue(PersonalTodoRules.isTodoNotification("todo", ""))
        assertTrue(PersonalTodoRules.isTodoNotification("", "todo_reminder"))
        assertFalse(PersonalTodoRules.isTodoNotification("work", "approval"))
    }

    @Test fun `server codes map to Vietnamese`() {
        assertEquals("Giờ nhắc phải ở tương lai.", PersonalTodoRules.errorMessage("Uncaught Error: TODO_REMIND_IN_PAST"))
        assertEquals("Việc này không còn tồn tại.", PersonalTodoRules.errorMessage("TODO_NOT_FOUND"))
        assertFalse(PersonalTodoRules.errorMessage("NEW_CODE").contains("NEW_CODE"))
    }
}
