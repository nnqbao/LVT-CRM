package lvt.crm.data.auth

import java.net.SocketTimeoutException
import java.net.UnknownHostException
import lvt.crm.data.convex.ConvexException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Only a real connectivity failure at start shows "Không có kết nối"; anything else goes to the sign-in screen. */
class ConnectivityFailureTest {
    @Test
    fun networkAndServerUnreachableAreConnectivityFailures() {
        assertTrue(isConnectivityFailure(UnknownHostException("decisive-puma-318.convex.cloud")))
        assertTrue(isConnectivityFailure(SocketTimeoutException("timeout")))
        assertTrue(isConnectivityFailure(ConvexException("HTTP_502", "Phản hồi Convex không hợp lệ (502).")))
    }

    @Test
    fun otherFailuresAreNot() {
        assertFalse(isConnectivityFailure(ConvexException("CONVEX_ERROR", "Server Error")))
        assertFalse(isConnectivityFailure(IllegalStateException("bad session payload")))
    }
}
