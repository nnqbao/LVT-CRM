package lvt.crm.ui.web

import java.net.URI
import lvt.crm.data.convex.ConvexException
import lvt.crm.push.NotificationDestination
import org.json.JSONObject

/**
 * Pure rules of the WebView app shell (unit-tested). The shell shows the web app
 * (`ConvexConfig.webUrl`) after the native sign-in; the bridge protocol is documented in the web
 * `src/lib/appBridge.js`.
 */
object WebShellRules {
    /** JavaScript object injected only into frames of the web app's origin. */
    const val BRIDGE_NAME = "LvtApp"

    /** `scheme://host[:port]` of the web app, the only origin allowed to talk to the bridge. */
    fun origin(webUrl: String): String {
        val uri = URI(webUrl.trim())
        val scheme = uri.scheme?.lowercase().orEmpty()
        val host = uri.host?.lowercase().orEmpty()
        require(scheme == "https" || (scheme == "http" && isLocalHost(host))) { "WEB_URL must be https" }
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "$scheme://$host$port"
    }

    private fun isLocalHost(host: String) = host == "localhost" || host == "127.0.0.1" || host == "10.0.2.2"

    /** Pages of the web app stay in the WebView; anything else opens outside the app. */
    fun isWebAppUrl(url: String, webUrl: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme != "https" && scheme != "http") return false
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "$scheme://${uri.host?.lowercase().orEmpty()}$port" == origin(webUrl)
    }

    /** Links the phone may open with another app (browser, mail, phone, maps). */
    fun isExternalLink(url: String): Boolean {
        val scheme = runCatching { URI(url).scheme?.lowercase() }.getOrNull() ?: return false
        return scheme in setOf("https", "http", "mailto", "tel", "geo")
    }

    /** `<input accept=".pdf,image/png">` → MIME types for the system file picker (any file when empty). */
    fun pickerMimeTypes(acceptTypes: Array<String>?): Array<String> {
        val types = acceptTypes.orEmpty()
            .flatMap { it.split(',') }
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .mapNotNull { type ->
                when {
                    type.contains('/') -> type
                    type.startsWith('.') -> EXTENSION_MIME[type.removePrefix(".")]
                    else -> null
                }
            }
            .distinct()
        return if (types.isEmpty()) arrayOf("*/*") else types.toTypedArray()
    }

    private val EXTENSION_MIME = mapOf(
        "pdf" to "application/pdf",
        "doc" to "application/msword",
        "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" to "application/vnd.ms-excel",
        "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "png" to "image/png",
        "jpg" to "image/jpeg",
        "jpeg" to "image/jpeg",
        "webp" to "image/webp",
    )

    /** MIME of a file handed over by the web: the web's claim, else from the file name. */
    fun mimeFor(name: String, claimed: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return EXTENSION_MIME[ext] ?: claimed.takeIf { it.contains('/') } ?: "application/octet-stream"
    }

    /** A file name safe for Downloads / cache (no path, control or reserved characters). */
    fun safeFileName(name: String): String {
        val cleaned = name.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[\\p{Cntrl}<>:\"|?*]"), "_")
            .trim()
            .trimStart('.')
            .take(120)
        return cleaned.ifBlank { "tai-lieu" }
    }

    /** Message for the web: open a tapped push notification like a bell item. */
    fun notificationMessage(destination: NotificationDestination): String =
        JSONObject()
            .put("type", "open-notification")
            .put(
                "item",
                JSONObject()
                    .put("key", destination.notificationKey.orEmpty())
                    .put("kind", destination.kind)
                    .put("sourceType", destination.sourceType)
                    .put("sourceId", destination.sourceId)
                    .put("menu", destination.menu),
            )
            .toString()

    fun handoffMessage(id: Int, code: String): String =
        JSONObject().put("type", "handoff").put("id", id).put("code", code).toString()

    /** `retry` = network trouble: the web asks again instead of signing out. */
    fun handoffFailedMessage(id: Int, retry: Boolean): String =
        JSONObject().put("type", "handoff-failed").put("id", id).put("retry", retry).toString()

    /** The app's own session is gone (signed out, revoked, locked, deactivated). */
    fun isSessionEnded(error: Throwable): Boolean {
        val text = listOfNotNull((error as? ConvexException)?.code, error.message).joinToString(" ")
        return SESSION_ENDED.any { text.contains(it, ignoreCase = true) }
    }

    private val SESSION_ENDED = listOf(
        "Unauthenticated",
        "Authentication",
        "UNAUTHENTICATED",
        "ACCOUNT_LOCKED",
        "USER_NOT_ACTIVE",
        "PASSWORD_CHANGE_REQUIRED",
    )
}
