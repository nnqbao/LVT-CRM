package lvt.crm.data.teaching

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GradeMathTest {
    @Test
    fun semesterAverageWeightsByCoefficient() {
        // Miệng 8, 15 phút 7,5, Thực hành 9 (hệ số 1) + Giữa kỳ 8 (hệ số 2): (8 + 7,5 + 9 + 16) / 5 = 8,1
        val average = GradeMath.semesterAverage(listOf(8.0 to 1, 7.5 to 1, 9.0 to 1, 8.0 to 2))
        assertEquals(8.1, average!!, 1e-9)
        assertEquals("8,1", GradeMath.formatScore(average))
        assertNull(GradeMath.semesterAverage(emptyList()))
    }

    @Test
    fun yearAndOverallAverages() {
        assertEquals(8.3, GradeMath.yearAverage(8.0, 8.5)!!, 1e-9) // (8 + 17) / 3 = 8,33
        assertNull(GradeMath.yearAverage(8.0, null))
        assertEquals(7.5, GradeMath.overallAverage(listOf(7.0, null, 8.0))!!, 1e-9)
        assertNull(GradeMath.overallAverage(listOf(null, null)))
    }

    @Test
    fun roundAverageRoundsHalfUp() {
        assertEquals(8.3, GradeMath.roundAverage(8.25), 1e-9)
        assertEquals(8.2, GradeMath.roundAverage(8.24), 1e-9)
        assertEquals(6.7, GradeMath.roundAverage(20.0 / 3), 1e-9)
    }

    @Test
    fun parseScoreAcceptsCommaOrDotUpToTwoDecimals() {
        assertEquals(8.5, GradeMath.parseScore("8,5")!!, 1e-9)
        assertEquals(7.25, GradeMath.parseScore(" 7.25 ")!!, 1e-9)
        assertEquals(10.0, GradeMath.parseScore("10")!!, 1e-9)
        assertEquals(0.0, GradeMath.parseScore("0")!!, 1e-9)
        assertEquals(9.5, GradeMath.parseScore("9,50")!!, 1e-9)
        assertNull(GradeMath.parseScore(""))
        assertNull(GradeMath.parseScore("10,5"))
        assertNull(GradeMath.parseScore("-1"))
        assertNull(GradeMath.parseScore("8,125"))
        assertNull(GradeMath.parseScore("8,5,1"))
        assertNull(GradeMath.parseScore("abc"))
        assertNull(GradeMath.parseScore(","))
    }

    @Test
    fun formatScoreUsesVietnameseDecimals() {
        assertEquals("—", GradeMath.formatScore(null))
        assertEquals("10,0", GradeMath.formatScore(10.0))
        assertEquals("7,5", GradeMath.formatScore(7.5))
        assertEquals("8,25", GradeMath.formatScore(8.25))
        assertEquals("8,5", GradeMath.editableScore(8.5))
        assertEquals("9", GradeMath.editableScore(9.0))
    }
}
