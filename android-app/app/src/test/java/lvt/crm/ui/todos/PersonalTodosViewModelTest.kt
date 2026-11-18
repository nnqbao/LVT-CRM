package lvt.crm.ui.todos

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.todos.PersonalTodo
import lvt.crm.data.todos.PersonalTodoInput
import lvt.crm.data.todos.PersonalTodoList
import lvt.crm.data.todos.PersonalTodoOperations
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PersonalTodosViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val now = 1792629600000L
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun teardown() { Dispatchers.resetMain() }

    @Test fun `create validates locally before calling the server`() = runTest(dispatcher) {
        val fake = FakeTodos()
        val vm = PersonalTodosViewModel(fake) { now }
        advanceUntilIdle()
        vm.startCreate()
        vm.saveDraft()
        assertEquals("Vui lòng nhập tên việc.", vm.uiState.value.draft?.errors?.get("title"))
        assertTrue(fake.calls.isEmpty())
        vm.setTitle("Nộp giáo án")
        vm.setRemindAt(now - 1)
        vm.saveDraft()
        assertEquals("Giờ nhắc phải ở tương lai.", vm.uiState.value.draft?.errors?.get("remind"))
        vm.setRemindAt(now + 60_000)
        vm.saveDraft()
        advanceUntilIdle()
        assertEquals(listOf("create"), fake.calls)
        assertNull(vm.uiState.value.draft)
        assertEquals("Đã thêm việc.", vm.uiState.value.message)
        assertEquals(1, vm.uiState.value.list?.open?.size)
    }

    @Test fun `edit keeps an already fired reminder and server errors stay in the form`() = runTest(dispatcher) {
        val fake = FakeTodos(listOf(PersonalTodo("t1", "A", "", null, now - 60_000, now - 60_000, null, 0, 0)))
        val vm = PersonalTodosViewModel(fake) { now }
        advanceUntilIdle()
        vm.startEdit(vm.uiState.value.list!!.open.single())
        fake.failNext = ConvexException("TODO_NOT_FOUND")
        vm.saveDraft()
        advanceUntilIdle()
        assertEquals("Việc này không còn tồn tại.", vm.uiState.value.draft?.serverError)
        vm.saveDraft()
        advanceUntilIdle()
        assertEquals(listOf("update", "update"), fake.calls)
        assertEquals("Đã lưu việc.", vm.uiState.value.message)
    }

    @Test fun `complete toggle and delete with confirmation`() = runTest(dispatcher) {
        val fake = FakeTodos(listOf(PersonalTodo("t1", "A", "", null, null, null, null, 0, 0)))
        val vm = PersonalTodosViewModel(fake) { now }
        advanceUntilIdle()
        val todo = vm.uiState.value.list!!.open.single()
        vm.setCompleted(todo, true)
        advanceUntilIdle()
        assertEquals(1, vm.uiState.value.list?.completed?.size)
        vm.requestDelete(vm.uiState.value.list!!.completed.single())
        assertNotNull(vm.uiState.value.confirmDelete)
        assertEquals(listOf("complete"), fake.calls)
        vm.confirmDelete()
        advanceUntilIdle()
        assertEquals(listOf("complete", "remove"), fake.calls)
        assertNull(vm.uiState.value.confirmDelete)
        assertEquals("Đã xóa việc.", vm.uiState.value.message)
        assertTrue(vm.uiState.value.list!!.completed.isEmpty())
    }

    @Test fun `notification focus highlights the todo and reloads`() = runTest(dispatcher) {
        val fake = FakeTodos()
        val vm = PersonalTodosViewModel(fake) { now }
        advanceUntilIdle()
        vm.focus("t9")
        advanceUntilIdle()
        assertEquals("t9", vm.uiState.value.focusId)
        assertEquals(2, fake.listCalls)
    }
}

private class FakeTodos(initial: List<PersonalTodo> = emptyList()) : PersonalTodoOperations {
    private val rows = initial.toMutableList()
    val calls = mutableListOf<String>()
    var listCalls = 0
    var failNext: Exception? = null

    override suspend fun listMine(): PersonalTodoList {
        listCalls++
        return PersonalTodoList(rows.filter { !it.done }, rows.filter { it.done })
    }

    private fun failIfRequested() {
        failNext?.let { failNext = null; throw it }
    }

    override suspend fun create(input: PersonalTodoInput): String {
        calls += "create"; failIfRequested()
        rows += PersonalTodo("t${rows.size + 1}", input.title, input.note.orEmpty(), input.dueAt, input.remindAt, null, null, 0, 0)
        return rows.last().id
    }

    override suspend fun update(id: String, input: PersonalTodoInput) {
        calls += "update"; failIfRequested()
        val index = rows.indexOfFirst { it.id == id }
        rows[index] = rows[index].copy(title = input.title, note = input.note.orEmpty(), dueAt = input.dueAt, remindAt = input.remindAt)
    }

    override suspend fun setCompleted(id: String, done: Boolean) {
        calls += "complete"; failIfRequested()
        val index = rows.indexOfFirst { it.id == id }
        rows[index] = rows[index].copy(completedAt = if (done) 1L else null)
    }

    override suspend fun remove(id: String) {
        calls += "remove"; failIfRequested()
        rows.removeAll { it.id == id }
    }
}
