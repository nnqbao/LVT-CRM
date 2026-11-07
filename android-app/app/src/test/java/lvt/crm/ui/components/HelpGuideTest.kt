package lvt.crm.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class HelpGuideTest {
    @Test
    fun embedUrlMatchesTheWebGuideEmbedUrl() {
        assertEquals(
            "https://lvt.vscgroup.io.vn/huong-dan-su-dung.html?embed=1#menu-cong-viec",
            HelpGuide.embedUrl("https://lvt.vscgroup.io.vn/", GuideAnchors.WORK),
        )
        assertEquals(
            "https://sandbox.example/huong-dan-su-dung.html?embed=1",
            HelpGuide.embedUrl("https://sandbox.example", null),
        )
    }

    @Test
    fun anchorsMirrorWebGuideAnchors() {
        assertEquals("menu-bao-cao", GuideAnchors.REPORTS)
        assertEquals("tb-thong-bao", GuideAnchors.NOTIFICATIONS)
        assertEquals("td-trao-doi", GuideAnchors.CHAT)
        assertEquals("menu-lich-cong-tac", GuideAnchors.DUTIES)
        assertEquals("menu-lop-chu-nhiem", GuideAnchors.HOMEROOM)
        assertEquals("menu-diem-danh", GuideAnchors.ATTENDANCE)
        assertEquals("bt-ban-tru", GuideAnchors.BOARDING)
        assertEquals("tai-khoan-ca-nhan", GuideAnchors.PROFILE)
    }
}
