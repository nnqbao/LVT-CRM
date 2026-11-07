package lvt.crm.ui.attendance

import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.attendance.AttendanceClass
import lvt.crm.data.attendance.AttendanceGrade
import lvt.crm.data.attendance.AttendanceOperations
import lvt.crm.data.attendance.AttendanceRoster
import lvt.crm.data.attendance.AttendanceSaveResult
import lvt.crm.data.attendance.AttendanceSaved
import lvt.crm.data.attendance.AttendanceStudent
import lvt.crm.data.attendance.AttendanceYear
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.homeroom.SchoolDay
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AttendanceViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun teardown() { Dispatchers.resetMain() }

    @Test fun `open class starts from server ticks and toggling marks it dirty`() = runTest(dispatcher) {
        val fake = FakeAttendance()
        val vm = AttendanceViewModel(fake)
        advanceUntilIdle()
        assertEquals(6, vm.uiState.value.grade)
        vm.toggleClass("c61")
        assertEquals(setOf("s2"), vm.uiState.value.draftAbsent)
        assertFalse(vm.uiState.value.dirty)
        vm.toggleAbsent("s1")
        assertEquals(setOf("s1", "s2"), vm.uiState.value.draftAbsent)
        assertTrue(vm.uiState.value.dirty)
        vm.toggleAbsent("not-in-class")
        assertEquals(setOf("s1", "s2"), vm.uiState.value.draftAbsent)
        vm.toggleAbsent("s1")
        assertFalse(vm.uiState.value.dirty)
    }

    @Test fun `unsaved ticks ask before collapsing switching grade or leaving`() = runTest(dispatcher) {
        val vm = AttendanceViewModel(FakeAttendance())
        advanceUntilIdle()
        vm.toggleClass("c61")
        vm.toggleAbsent("s1")
        vm.selectGrade(7)
        assertEquals(6, vm.uiState.value.grade)
        assertEquals(AttendancePendingAction.SelectGrade(7), vm.uiState.value.pendingAction)
        vm.cancelDiscard()
        assertNull(vm.uiState.value.pendingAction)
        assertTrue(vm.uiState.value.dirty)
        vm.toggleClass("c61")
        assertEquals(AttendancePendingAction.ToggleClass("c61"), vm.uiState.value.pendingAction)
        vm.confirmDiscard()
        assertNull(vm.uiState.value.openClassId)
        assertFalse(vm.uiState.value.dirty)
        // Clean state: leaving is allowed right away.
        assertTrue(vm.requestLeave())
        vm.toggleClass("c61")
        vm.toggleAbsent("s1")
        assertFalse(vm.requestLeave())
        assertEquals(AttendancePendingAction.Leave, vm.uiState.value.pendingAction)
        val before = vm.leaveRequests.value
        vm.confirmDiscard()
        assertEquals(before + 1, vm.leaveRequests.value)
        assertFalse(vm.uiState.value.dirty)
    }

    @Test fun `save sends the draft then reloads and shows the result`() = runTest(dispatcher) {
        val fake = FakeAttendance()
        val vm = AttendanceViewModel(fake)
        advanceUntilIdle()
        vm.toggleClass("c61")
        vm.toggleAbsent("s1")
        vm.saveOpenClass()
        assertTrue(vm.uiState.value.saving)
        vm.toggleAbsent("s3")
        advanceUntilIdle()
        assertEquals(listOf(Triple("2026-10-22", "c61", setOf("s1", "s2"))), fake.saves)
        assertFalse(vm.uiState.value.saving)
        assertEquals("Đã lưu lớp 6-1: 2 vắng, 1 có mặt.", vm.uiState.value.saveMessage)
        assertEquals(setOf("s1", "s2"), vm.uiState.value.draftAbsent)
        assertFalse(vm.uiState.value.dirty)
        assertNotNull(vm.uiState.value.openClass?.saved)
        assertEquals(2, fake.rosterCalls)
    }

    @Test fun `save failure keeps the draft and shows a Vietnamese error`() = runTest(dispatcher) {
        val fake = FakeAttendance().apply { saveError = ConvexException("ATTENDANCE_DATE_TODAY_ONLY") }
        val vm = AttendanceViewModel(fake)
        advanceUntilIdle()
        vm.toggleClass("c61")
        vm.toggleAbsent("s1")
        vm.saveOpenClass()
        advanceUntilIdle()
        assertEquals("Giám thị chỉ được điểm danh cho ngày hôm nay.", vm.uiState.value.saveError)
        assertTrue(vm.uiState.value.dirty)
        assertEquals(setOf("s1", "s2"), vm.uiState.value.draftAbsent)
    }

    @Test fun `confirmed save with failed read-back marks the class saved locally`() = runTest(dispatcher) {
        val fake = FakeAttendance()
        val vm = AttendanceViewModel(fake)
        advanceUntilIdle()
        vm.toggleClass("c61")
        vm.toggleAbsent("s1")
        fake.rosterError = IOException("offline")
        vm.saveOpenClass()
        advanceUntilIdle()
        assertEquals(1, fake.saves.size)
        assertFalse(vm.uiState.value.saving)
        assertFalse(vm.uiState.value.dirty)
        assertNotNull(vm.uiState.value.openClass?.saved)
        assertTrue(vm.uiState.value.saveMessage!!.contains("Chưa tải lại"))
    }

    @Test fun `Giam thi cannot pick another date and admin cannot pick the future`() = runTest(dispatcher) {
        val supervisor = FakeAttendance()
        val vm = AttendanceViewModel(supervisor)
        advanceUntilIdle()
        vm.selectDate("2026-10-21")
        advanceUntilIdle()
        assertEquals(1, supervisor.rosterCalls)
        val admin = FakeAttendance(canChooseDate = true)
        val adminVm = AttendanceViewModel(admin)
        advanceUntilIdle()
        adminVm.selectDate("2026-10-23")
        advanceUntilIdle()
        assertEquals(1, admin.rosterCalls)
        adminVm.selectDate("2026-10-21")
        advanceUntilIdle()
        assertEquals(listOf(null, "2026-10-21"), admin.requestedDates)
        assertEquals("2026-10-21", adminVm.uiState.value.roster?.date)
    }

    @Test fun `load errors are mapped and an older load cannot overwrite a newer date`() = runTest(dispatcher) {
        val failing = FakeAttendance().apply { rosterError = ConvexException("SUPERVISOR_REQUIRED") }
        val vm = AttendanceViewModel(failing)
        advanceUntilIdle()
        assertEquals("Chỉ Giám thị hoặc Admin/Mod mới được điểm danh.", vm.uiState.value.error)
        assertNull(vm.uiState.value.roster)

        val slow = FakeAttendance(canChooseDate = true)
        val adminVm = AttendanceViewModel(slow)
        advanceUntilIdle()
        slow.block = CompletableDeferred()
        adminVm.selectDate("2026-10-20")
        runCurrent()
        val blocked = slow.block!!
        slow.block = null
        adminVm.selectDate("2026-10-21")
        advanceUntilIdle()
        blocked.complete(Unit)
        advanceUntilIdle()
        assertEquals("2026-10-21", adminVm.uiState.value.roster?.date)
    }
}

private class FakeAttendance(private val canChooseDate: Boolean = false) : AttendanceOperations {
    var rosterCalls = 0
    val requestedDates = mutableListOf<String?>()
    val saves = mutableListOf<Triple<String, String, Set<String>>>()
    var saveError: Exception? = null
    var rosterError: Exception? = null
    var block: CompletableDeferred<Unit>? = null
    private var saved: AttendanceSaved? = null
    private var absent = setOf("s2")

    override suspend fun roster(date: String?): AttendanceRoster {
        rosterCalls++
        requestedDates += date
        block?.await()
        rosterError?.let { throw it }
        val day = date ?: "2026-10-22"
        val students = listOf("s1" to "An", "s2" to "Bình", "s3" to "Chi").mapIndexed { index, (id, name) ->
            AttendanceStudent(id, name, index + 1, id in absent)
        }
        return AttendanceRoster(
            date = day,
            today = "2026-10-22",
            canChooseDate = canChooseDate,
            schoolYear = AttendanceYear("year", "2026–2027", "2026-09-01", "2027-05-31"),
            schoolDay = SchoolDay(true, "default_school_day", "", false),
            grades = listOf(
                AttendanceGrade(6, listOf(AttendanceClass("c61", "6-1", "6-1", 6, saved, students))),
                AttendanceGrade(7, emptyList()),
            ),
        )
    }

    override suspend fun saveClass(date: String, classId: String, absentStudentIds: Set<String>): AttendanceSaveResult {
        saves += Triple(date, classId, absentStudentIds)
        saveError?.let { throw it }
        absent = absentStudentIds
        saved = AttendanceSaved(1792629600000, "GT", "manual", 3 - absentStudentIds.size, absentStudentIds.size)
        return AttendanceSaveResult(classId, 1792629600000, 3 - absentStudentIds.size, absentStudentIds.size, 1)
    }
}
