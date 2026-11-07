package lvt.crm.ui.web

import lvt.crm.data.convex.ConvexException
import lvt.crm.push.NotificationDestination
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WebShellRulesTest {
    private val web = "https://lvt.vscgroup.io.vn"

    @Test
    fun bridgeOriginIsTheWebAppOnly() {
        assertEquals("https://lvt.vscgroup.io.vn", WebShellRules.origin("https://lvt.vscgroup.io.vn/"))
        assertEquals("https://sandbox.example:8443", WebShellRules.origin("https://Sandbox.Example:8443/x"))
        assertEquals("http://10.0.2.2:3009", WebShellRules.origin("http://10.0.2.2:3009"))
        assertTrue(runCatching { WebShellRules.origin("http://lvt.vscgroup.io.vn") }.isFailure)
    }

    @Test
    fun onlyWebAppPagesStayInTheWebView() {
        assertTrue(WebShellRules.isWebAppUrl("https://lvt.vscgroup.io.vn/cong-viec?x=1#a", web))
        assertTrue(WebShellRules.isWebAppUrl("https://LVT.vscgroup.io.vn/huong-dan-su-dung.html", web))
        assertFalse(WebShellRules.isWebAppUrl("https://lvt.vscgroup.io.vn.evil.com/", web))
        assertFalse(WebShellRules.isWebAppUrl("http://lvt.vscgroup.io.vn/", web))
        assertFalse(WebShellRules.isWebAppUrl("https://www.youtube.com/watch?v=1", web))
        assertFalse(WebShellRules.isWebAppUrl("javascript:alert(1)", web))
        assertTrue(WebShellRules.isExternalLink("https://www.youtube.com/"))
        assertTrue(WebShellRules.isExternalLink("mailto:a@b.vn"))
        assertFalse(WebShellRules.isExternalLink("intent://x#Intent;end"))
        assertFalse(WebShellRules.isExternalLink("file:///sdcard/x"))
    }

    @Test
    fun fileInputAcceptBecomesPickerMimeTypes() {
        assertArrayEquals(
            arrayOf("application/pdf", "image/png", "image/jpeg"),
            WebShellRules.pickerMimeTypes(arrayOf(".pdf,.png,.jpg,.jpeg")),
        )
        assertArrayEquals(
            arrayOf("image/jpeg", "image/png", "image/webp"),
            WebShellRules.pickerMimeTypes(arrayOf("image/jpeg,image/png,image/webp,.jpg,.jpeg,.png,.webp")),
        )
        assertArrayEquals(arrayOf("*/*"), WebShellRules.pickerMimeTypes(arrayOf("")))
        assertArrayEquals(arrayOf("*/*"), WebShellRules.pickerMimeTypes(null))
    }

    @Test
    fun handedOverFilesGetSafeNamesAndTypes() {
        assertEquals("bao-cao.pdf", WebShellRules.safeFileName("../../bao-cao.pdf"))
        assertEquals("Công văn_1_.docx", WebShellRules.safeFileName("Công văn:1?.docx"))
        assertEquals("tai-lieu", WebShellRules.safeFileName("..."))
        assertEquals("application/pdf", WebShellRules.mimeFor("a.PDF", "text/html"))
        assertEquals("text/csv", WebShellRules.mimeFor("a.csv", "text/csv"))
        assertEquals("application/octet-stream", WebShellRules.mimeFor("a.bin", ""))
    }

    @Test
    fun bridgeMessages() {
        val open = JSONObject(
            WebShellRules.notificationMessage(
                NotificationDestination("people", "staff_fault", "f1", "people:staff_fault:f1", menu = "staff-faults"),
            ),
        )
        assertEquals("open-notification", open.getString("type"))
        val item = open.getJSONObject("item")
        assertEquals("people:staff_fault:f1", item.getString("key"))
        assertEquals("staff-faults", item.getString("menu"))
        assertEquals("f1", item.getString("sourceId"))
        val handoff = JSONObject(WebShellRules.handoffMessage(7, "code"))
        assertEquals(7, handoff.getInt("id"))
        assertEquals("code", handoff.getString("code"))
        assertTrue(JSONObject(WebShellRules.handoffFailedMessage(7, retry = true)).getBoolean("retry"))
        assertFalse(JSONObject(WebShellRules.handoffFailedMessage(7, retry = false)).getBoolean("retry"))
    }

    @Test
    fun onlyAnEndedSessionSignsTheAppOut() {
        assertTrue(WebShellRules.isSessionEnded(ConvexException("UNAUTHENTICATED")))
        assertTrue(WebShellRules.isSessionEnded(ConvexException("CONVEX_ERROR", "Uncaught Error: ACCOUNT_LOCKED")))
        assertTrue(WebShellRules.isSessionEnded(IllegalStateException("Unauthenticated call")))
        assertFalse(WebShellRules.isSessionEnded(java.net.UnknownHostException("lvt.vscgroup.io.vn")))
        assertFalse(WebShellRules.isSessionEnded(ConvexException("HTTP_502", "Phản hồi Convex không hợp lệ (502).")))
    }
}
