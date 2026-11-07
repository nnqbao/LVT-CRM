package lvt.crm.data.attendance

import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AttendanceRepositoryTest {
    private fun rosterJson(date: String = "2026-10-22", saved: String = "null") = JSONObject(
        """{"date":"$date","today":"2026-10-22","canChooseDate":false,
        "schoolYear":{"_id":"year","name":"2026–2027","startDate":"2026-09-01","endDate":"2027-05-31"},
        "schoolDay":{"isSchoolDay":true,"kind":"default_school_day","outsideYear":false},
        "grades":[
          {"gradeLevel":6,"classes":[
            {"classId":"c61","code":"6-1","name":"6-1","gradeLevel":6,"saved":$saved,"students":[
              {"studentId":"s1","fullName":"An","rosterNumber":1,"absent":false},
              {"studentId":"s2","fullName":"Bình","rosterNumber":null,"absent":true}]},
            {"classId":"c62","code":"6-2","name":"6-2","gradeLevel":6,"saved":null,"students":[]}]},
          {"gradeLevel":7,"classes":[]},{"gradeLevel":8,"classes":[]},{"gradeLevel":9,"classes":[]}]}""",
    )

    @Test fun `roster decodes grades classes saved marker and absent ticks`() {
        val roster = decodeAttendanceRoster(rosterJson(saved = """{"savedAt":1792648800000,"savedByName":"GT","source":"manual","presentCount":1,"absentCount":1}"""))
        assertEquals("2026-10-22", roster.date)
        assertFalse(roster.canChooseDate)
        assertEquals("2026–2027", roster.schoolYear?.name)
        assertEquals(listOf(6, 7, 8, 9), roster.grades.map { it.gradeLevel })
        val klass = roster.findClass("c61")!!
        assertEquals(setOf("s2"), klass.absentIds)
        assertNull(klass.students[1].rosterNumber)
        assertEquals(1, roster.grade(6).savedCount)
        assertEquals(2, roster.grade(6).classes.size)
        assertEquals(0, roster.grade(10).classes.size)
        assertEquals(1, klass.saved?.absentCount)
    }

    @Test fun `no school year and malformed rosters`() {
        val noYear = decodeAttendanceRoster(JSONObject("""{"date":"2026-10-22","today":"2026-10-22","canChooseDate":true,"schoolYear":null,"schoolDay":{"isSchoolDay":false,"kind":"default_weekend","outsideYear":false},"grades":[{"gradeLevel":6,"classes":[]}]}"""))
        assertNull(noYear.schoolYear)
        assertTrue(noYear.canChooseDate)
        for (bad in listOf("{}", """{"date":"2026-02-30","today":"2026-10-22","grades":[]}""")) {
            assertTrue(bad, runCatching { decodeAttendanceRoster(JSONObject(bad)) }.isFailure)
        }
        val duplicate = rosterJson().toString().replace("\"studentId\":\"s2\"", "\"studentId\":\"s1\"")
        assertTrue(runCatching { decodeAttendanceRoster(JSONObject(duplicate)) }.isFailure)
    }

    @Test fun `save sends exact args and checks the acknowledgment`() = runTest {
        val writes = mutableListOf<Pair<String, JSONObject>>()
        val repository = AttendanceRepository(
            { _, _ -> rosterJson() },
            { path, args ->
                writes += path to args
                JSONObject().put("classId", args.getString("classId")).put("savedAt", 1792648800000).put("presentCount", 39).put("absentCount", args.getJSONArray("absentStudentIds").length()).put("changedCount", 2)
            },
        )
        val result = repository.saveClass("2026-10-22", "c61", setOf("s2", "s1"))
        assertEquals("supervisorAttendance:saveClass", writes.single().first)
        val args = writes.single().second
        assertEquals(setOf("date", "classId", "absentStudentIds"), args.keys().asSequence().toSet())
        assertEquals("[\"s1\",\"s2\"]", args.getJSONArray("absentStudentIds").toString())
        assertEquals(2, result.absentCount)
        val wrongClass = AttendanceRepository({ _, _ -> rosterJson() }, { _, _ -> JSONObject().put("classId", "other").put("savedAt", 1).put("presentCount", 0).put("absentCount", 0) })
        assertTrue(runCatching { wrongClass.saveClass("2026-10-22", "c61", emptySet()) }.isFailure)
        assertTrue(runCatching { repository.saveClass("2026-13-01", "c61", emptySet()) }.isFailure)
        assertTrue(runCatching { repository.saveClass("2026-10-22", "c61", (1..201).map { "s$it" }.toSet()) }.isFailure)
        assertEquals(1, writes.size)
    }

    @Test fun `roster query passes the chosen date and rejects a mismatched reply`() = runTest {
        var lastArgs: JSONObject? = null
        val repository = AttendanceRepository({ _, args -> lastArgs = args; rosterJson() }, { _, _ -> error("no writes") })
        repository.roster(null)
        assertFalse(lastArgs!!.has("date"))
        repository.roster("2026-10-22")
        assertEquals("2026-10-22", lastArgs!!.getString("date"))
        assertTrue(runCatching { repository.roster("2026-10-21") }.isFailure)
    }

    @Test fun `presentation wording matches the web`() {
        assertEquals("Chưa điểm danh", AttendancePresentation.classStatusText(null))
        // 2026-10-22T07:40:00+07:00
        val saved = AttendanceSaved(1792629600000, "", "manual", 38, 2)
        assertEquals("07:40", AttendancePresentation.vietnamHm(saved.savedAt))
        assertEquals("Đã lưu 07:40 · 2 vắng", AttendancePresentation.classStatusText(saved))
        assertEquals("Lưu lớp 6-1 (3 vắng)", AttendancePresentation.saveButtonLabel("6-1", 3, saving = false))
        assertEquals("Đang lưu…", AttendancePresentation.saveButtonLabel("6-1", 3, saving = true))
        assertEquals("3 vắng · 37 có mặt", AttendancePresentation.countSummary(40, 3))
        assertEquals(setOf("a", "b"), AttendancePresentation.toggle(setOf("a"), "b"))
        assertEquals(emptySet<String>(), AttendancePresentation.toggle(setOf("a"), "a"))
        assertEquals(listOf(6, 7, 8, 9), AttendancePresentation.tabs(null))
        assertEquals(listOf(5, 6, 7, 8, 9), AttendancePresentation.tabs(decodeAttendanceRoster(rosterJson()).let { it.copy(grades = it.grades + AttendanceGrade(5, emptyList())) }))
    }

    @Test fun `server error codes map to Vietnamese and never leak raw codes`() {
        assertEquals("Giám thị chỉ được điểm danh cho ngày hôm nay.", AttendancePresentation.errorMessage("Uncaught Error: ATTENDANCE_DATE_TODAY_ONLY at handler"))
        assertEquals("Chỉ Giám thị hoặc Admin/Mod mới được điểm danh.", AttendancePresentation.errorMessage("SUPERVISOR_REQUIRED"))
        assertTrue(AttendancePresentation.errorMessage("ATTENDANCE_STUDENT_NOT_IN_CLASS").contains("tải lại"))
        assertTrue(AttendancePresentation.errorMessage("ATTENDANCE_CAMERA_IMPORT_RETIRED").contains("menu Điểm danh"))
        assertEquals("Bạn không có quyền thực hiện thao tác này.", AttendancePresentation.errorMessage("FORBIDDEN"))
        val unknown = AttendancePresentation.errorMessage("SOME_NEW_CODE")
        assertFalse(unknown.contains("SOME_NEW_CODE"))
    }
}
