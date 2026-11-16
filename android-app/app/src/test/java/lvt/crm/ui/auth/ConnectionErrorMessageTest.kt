package lvt.crm.ui.auth

import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import lvt.crm.data.convex.ConvexException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The sign-in screen explains network trouble in Vietnamese, never with the raw Java/HTTP text. */
class ConnectionErrorMessageTest {
    @Test
    fun offlineSaysThereIsNoNetwork() {
        val offline = "Không có kết nối mạng. Hãy bật Wi-Fi hoặc dữ liệu di động (4G) rồi thử lại."
        assertEquals(
            offline,
            connectionErrorMessage(UnknownHostException("Unable to resolve host \"convex.thcslevantam.ai.vn\": No address associated with hostname")),
        )
        assertEquals(offline, connectionErrorMessage(ConnectException("Failed to connect")))
    }

    @Test
    fun slowOrBrokenConnectionAndServerOutagesAreExplained() {
        assertTrue(connectionErrorMessage(SocketTimeoutException("timeout"))!!.startsWith("Mạng chậm"))
        assertTrue(connectionErrorMessage(IOException("unexpected end of stream"))!!.startsWith("Không kết nối được máy chủ"))
        val outage = connectionErrorMessage(ConvexException("HTTP_502", "Phản hồi Convex không hợp lệ (502)."))!!
        assertTrue(outage.contains("mã 502"))
        assertFalse(outage.contains("Convex"))
    }

    @Test
    fun otherFailuresKeepTheirOwnMessage() {
        assertNull(connectionErrorMessage(ConvexException("INVALID_CREDENTIALS", "Sai email hoặc mật khẩu.")))
        assertNull(connectionErrorMessage(IllegalArgumentException("EMAIL_PASSWORD_REQUIRED")))
    }
}
