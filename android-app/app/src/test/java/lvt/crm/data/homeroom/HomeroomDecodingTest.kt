package lvt.crm.data.homeroom

import java.time.Instant
import lvt.crm.data.auth.MenuAccess
import lvt.crm.data.auth.decodeUserSession
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HomeroomDecodingTest {
    private fun session(access: Any? = null, role: String = "user", status: String = "active", password: Boolean = false, attendance: Any? = null, work: Any? = null) =
        decodeUserSession(JSONObject().put("user", JSONObject().put("_id", "test-user").put("role", role)
            .put("status", status).put("mustChangePassword", password))
            .put("menuAccess", JSONObject().put("homeroom", access).put("attendance", attendance).put("work", work)))!!

    @Test fun `menu decoding fails closed and gates inactive password sessions`() {
        for (access in listOf(null, "unknown", true, 1, JSONObject())) assertFalse(session(access).canSeeHomeroom)
        assertEquals(MenuAccess.View, session("edit").homeroomAccess)
        assertTrue(session("view_all").canSeeHomeroom)
        // Giám thị is no longer valid on homeroom: it resolves to hidden, never to a homeroom view.
        assertFalse(session("supervisor").canSeeHomeroom)
        assertEquals(MenuAccess.Hidden, session("supervisor").homeroomAccess)
        assertTrue(session(role = "admin").canSeeHomeroom)
        assertTrue(session(role = "moderator").canSeeHomeroom)
        assertFalse(session(role = "admin", status = "inactive").canSeeHomeroom)
        val missingMenu = JSONObject().put("user", JSONObject().put("_id", "test-user").put("status", "active"))
        assertFalse(decodeUserSession(missingMenu)!!.canSeeHomeroom)
        assertFalse(decodeUserSession(missingMenu.put("menuAccess", JSONArray()))!!.canSeeHomeroom)
        assertFalse(session("view", status = "inactive").canSeeHomeroom)
        assertFalse(session(role = "admin", password = true).canSeeHomeroom)
    }

    @Test fun `attendance menu is Giam thi only and work visibility follows the work menu`() {
        assertTrue(session(attendance = "supervisor").isAttendanceSupervisor)
        assertTrue(session(attendance = "supervisor").canSeeAttendance)
        assertFalse(session(attendance = "supervisor").canSeeHomeroom)
        for (level in listOf(null, "hidden", "view", "view_all", "edit", "unknown")) {
            assertFalse("$level", session(attendance = level).canSeeAttendance)
        }
        // A homeroom teacher who is also Giám thị sees both menus.
        assertTrue(session("view", attendance = "supervisor").let { it.canSeeHomeroom && it.canSeeAttendance })
        // Admin/mod see Điểm danh by role but are not "Giám thị".
        for (role in listOf("admin", "moderator")) {
            assertTrue(session(role = role).canSeeAttendance)
            assertFalse(session(role = role, attendance = "supervisor").isAttendanceSupervisor)
            assertTrue(session(role = role).canSeeWork)
        }
        assertFalse(session(attendance = "supervisor", status = "inactive").canSeeAttendance)
        assertFalse(session(attendance = "supervisor", password = true).canSeeAttendance)
        assertTrue(session(work = "view").canSeeWork)
        assertTrue(session(work = "view_all").canSeeWork)
        assertFalse(session(work = "hidden").canSeeWork)
        assertFalse(session(work = null).canSeeWork)
        assertFalse(session(work = "supervisor").canSeeWork)
    }

    @Test fun `Vietnam date midnight and invalid calendar dates`() {
        assertEquals("2026-10-08", vietnamToday(Instant.parse("2026-10-07T17:00:00Z")))
        assertEquals("2026-10-07", vietnamToday(Instant.parse("2026-10-07T16:59:59Z")))
        assertTrue(isVietnamDate("2024-02-29"))
        for (date in listOf("2026-02-29", "2026-02-30", "2026-13-01", "2026-1-01", "bad")) assertFalse(isVietnamDate(date))
    }

    @Test fun `no data remains separate from absence and empty classes are real empty`() {
        val result = decodeOverview(JSONObject("""{"date":"2026-10-07","today":"2026-10-07","mode":"teacher",
            "schoolYear":{"_id":"test-year","name":"2026–2027"},"classes":[],"schoolDay":{},"missingUpload":{},
            "summary":{"counts":{"present":0,"late":0,"absent_excused":0,"absent_unexcused":0,"no_data":3,"absent_pending":2,"exempt":0},"ratedRows":2,"totalRows":5,"attendanceRate":0}}"""))
        assertEquals(3, result.counts.noData)
        assertEquals(2, result.counts.absent)
        assertTrue(result.classes.isEmpty())
        assertEquals(0, decodeSchoolYears(JSONArray()).size)
    }

    @Test fun `class rows carry the Giam thi saved flag with legacy published fallback`() {
        fun overview(classes: String) = decodeOverview(JSONObject("""{"date":"2026-10-07","today":"2026-10-07","mode":"school",
            "schoolYear":{"_id":"test-year","name":"2026–2027"},"classes":[$classes],"schoolDay":{},"missingUpload":{"shouldAlert":true,"cutoffTime":"08:00","missingClasses":[{"classId":"c2","code":"6-2","name":"Lớp 6-2"}]},
            "summary":{"counts":{"present":0,"late":0,"absent_excused":0,"absent_unexcused":0,"no_data":0,"absent_pending":0,"exempt":0}}}"""))
        val counts = """"counts":{"present":0,"late":0,"absent_excused":0,"absent_unexcused":0,"no_data":0,"absent_pending":0,"exempt":0}"""
        val result = overview("""{"_id":"c1","code":"6-1","name":"Lớp 6-1","published":true,"saved":true,$counts},{"_id":"c2","code":"6-2","name":"Lớp 6-2","published":false,"saved":false,$counts},{"_id":"c3","code":"6-3","name":"Lớp 6-3","published":true,$counts}""")
        assertEquals(listOf(true, false, true), result.classes.map { it.saved })
        assertEquals(listOf("Lớp 6-2"), result.missingUpload.missingClassCodes)
    }

    @Test fun `malformed responses do not masquerade as empty successful data`() {
        assertTrue(runCatching { decodeOverview(JSONObject()) }.isFailure)
        assertTrue(runCatching { decodeSchoolYears(null) }.isFailure)
    }
}
