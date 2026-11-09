package lvt.crm.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class IconTabBarTest {
    @Test
    fun badgeTextHidesZeroAndNegativeCounts() {
        assertNull(iconTabBadgeText(0))
        assertNull(iconTabBadgeText(-3))
    }

    @Test
    fun badgeTextCapsAtNinetyNinePlus() {
        assertEquals("1", iconTabBadgeText(1))
        assertEquals("99", iconTabBadgeText(99))
        assertEquals("99+", iconTabBadgeText(100))
        assertEquals("99+", iconTabBadgeText(4_200))
    }

    @Test
    fun contentDescriptionMergesLabelAndBadge() {
        assertEquals("Quá hạn, 3", iconTabContentDescription("Quá hạn", 3))
        assertEquals("Việc cần làm, 99+", iconTabContentDescription("Việc cần làm", 120))
        assertEquals("Tổng quan", iconTabContentDescription("Tổng quan", 0))
    }
}
