package lvt.crm.data.boarding

import lvt.crm.data.auth.MenuAccess
import lvt.crm.data.auth.UserSession
import lvt.crm.data.convex.ConvexHttpClient
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BoardingRulesTest {
    // 2026-10-22 12:00 Vietnam / 2026-03-01 12:00 Vietnam
    private val october = 1_792_645_200_000L
    private val march = 1_772_341_200_000L

    @Test
    fun periodLabelMatchesWebHelper() {
        assertEquals("Học kỳ 1 · Năm học 2026-2027", BoardingRules.periodLabel(1, "2026-2027"))
        assertEquals("Học kỳ 2", BoardingRules.periodLabel(2, "2026-2027", short = true))
        assertEquals("Học kỳ 2", BoardingRules.periodLabel(2, ""))
        assertEquals("Chưa có kỳ bán trú", BoardingRules.periodLabel(null))
    }

    @Test
    fun schoolYearStartsInJuly() {
        assertEquals("2026-2027", BoardingRules.currentSchoolYear(october))
        assertEquals("2025-2026", BoardingRules.currentSchoolYear(march))
        val options = BoardingRules.schoolYearOptions(october)
        assertEquals(7, options.size)
        assertEquals("2024-2025", options.first())
        assertEquals("2026-2027", options[2])
        assertTrue("2019-2020" in BoardingRules.schoolYearOptions(october, include = "2019-2020"))
    }

    @Test
    fun validationMatchesServerCleanInput() {
        assertNull(BoardingRules.validate(BoardingPeriodInput(1, "2026-2027", listOf("u1"))))
        assertEquals("Học kỳ chỉ được chọn 1 hoặc 2.", BoardingRules.validate(BoardingPeriodInput(3, "2026-2027", listOf("u1"))))
        assertEquals("Năm học không hợp lệ.", BoardingRules.validate(BoardingPeriodInput(1, "2026-2028", listOf("u1"))))
        assertEquals("Vui lòng chọn ít nhất một giáo viên.", BoardingRules.validate(BoardingPeriodInput(2, "2026-2027", listOf(" "))))
        assertFalse(BoardingRules.hasPeriodForYear(listOf(BoardingPeriod("p", 1, "2025-2026")), "2026-2027"))
    }

    @Test
    fun serverErrorsUseWebMessages() {
        val raw = "[CONVEX M(boarding:create)] Server Error Uncaught Error: BOARDING_PERIOD_EXISTS at handler"
        assertEquals("Kỳ bán trú này đã tồn tại.", ConvexHttpClient.humanize(raw))
        assertEquals("BOARDING_PERIOD_EXISTS", ConvexHttpClient.extractCode(raw))
        // INVALID_* must not become the login message.
        assertEquals("Năm học không hợp lệ.", ConvexHttpClient.humanize("Uncaught Error: INVALID_SCHOOL_YEAR"))
        assertEquals("BOARDING_PERIOD_FORBIDDEN", ConvexHttpClient.extractCode("Error: BOARDING_PERIOD_FORBIDDEN"))
        assertEquals(BoardingErrorMessages.FALLBACK, BoardingErrorMessages.messageFor(IllegalStateException("boom")))
    }

    @Test
    fun decodesReport() {
        val report = decodeBoardingReport(
            JSONObject(
                """
                {"visibilityScope":"department",
                 "periods":[{"_id":"p2","semester":2,"schoolYear":"2026-2027","participantCount":3}],
                 "selectedPeriod":{"_id":"p2","semester":2,"schoolYear":"2026-2027"},
                 "groups":[{"departmentName":"Tổ Toán","participantCount":1,
                            "participants":[{"_id":"u1","name":"An","email":"an@x.vn","departmentName":"Tổ Toán","positionName":"Giáo viên"}]}],
                 "totalParticipants":1}
                """.trimIndent(),
            ),
        )
        assertFalse(report.isSchoolWide)
        assertEquals("p2", report.selectedPeriod?.id)
        assertEquals(3, report.periods.single().participantCount)
        assertEquals("Giáo viên", report.groups.single().participants.single().positionName)
        val empty = decodeBoardingReport(JSONObject("""{"visibilityScope":"all","periods":[],"selectedPeriod":null,"groups":[],"totalParticipants":0}"""))
        assertTrue(empty.isSchoolWide)
        assertNull(empty.selectedPeriod)
    }

    @Test
    fun decodesAdminList() {
        val admin = decodeBoardingAdmin(
            JSONObject(
                """
                {"users":[{"_id":"u1","name":"An","email":"","departmentName":"","positionName":""}],
                 "periods":[{"_id":"p1","semester":1,"schoolYear":"2026-2027","participantUserIds":["u1","u2"],
                             "participants":[{"_id":"u1","name":"An"}],"active":true}]}
                """.trimIndent(),
            ),
        )
        assertEquals(1, admin.users.size)
        val period = admin.periods.single()
        assertEquals(listOf("u1", "u2"), period.participantUserIds)
        assertEquals(2, period.period.participantCount)
        assertEquals(1, period.participants.size)
    }

    @Test
    fun visibilityFollowsReportsMenu() {
        fun session(role: String, reports: MenuAccess?) = UserSession(
            userId = "u", email = "u@x.vn", name = "U", role = role, status = "active",
            menuAccess = reports?.let { mapOf("reports" to it) } ?: emptyMap(),
        )
        assertTrue(session("admin", null).canSeeBoarding)
        assertTrue(session("moderator", null).canManageBoarding)
        assertTrue(session("user", MenuAccess.View).canSeeBoarding)
        assertTrue(session("user", MenuAccess.ViewAll).canSeeBoarding)
        assertFalse(session("user", MenuAccess.View).canManageBoarding)
        assertFalse(session("user", MenuAccess.Hidden).canSeeBoarding)
        assertFalse(session("user", null).canSeeBoarding)
        assertFalse(session("user", MenuAccess.Supervisor).canSeeBoarding)
        assertFalse(session("user", MenuAccess.View).copy(mustChangePassword = true).canSeeBoarding)
    }
}
