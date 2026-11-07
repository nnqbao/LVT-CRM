package lvt.crm.ui.web

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebResourceErrorCompat
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import lvt.crm.AppContainer
import lvt.crm.BuildConfig
import lvt.crm.data.auth.UserSession
import lvt.crm.data.convex.ConvexConfig
import lvt.crm.push.NotificationDestination
import lvt.crm.ui.auth.findFragmentActivity
import org.json.JSONObject

/**
 * The signed-in app: the web app (same menus, screens and guide videos as the browser) in a
 * WebView. Native parts: sign-in (password, vân tay, passkey) before this screen, push
 * notifications, files, vân tay / passkey settings and the "Không có kết nối" screen.
 *
 * The WebView gets its own session through a single-use code (convex/appHandoff.ts) sent over
 * the origin-restricted `LvtApp` bridge; protocol in the web `src/lib/appBridge.js`.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebAppShell(
    container: AppContainer,
    session: UserSession,
    notificationDestination: NotificationDestination?,
    onNotificationDestinationHandled: () -> Unit,
    onSignOut: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val webUrl = ConvexConfig.webUrl
    val origin = remember(webUrl) { WebShellRules.origin(webUrl) }
    val files = remember { WebFiles(context.applicationContext) }
    var loadFailed by remember { mutableStateOf(false) }
    var handoffFailed by remember { mutableStateOf(false) }
    var online by remember { mutableStateOf(isOnline(context)) }
    var webReady by remember { mutableStateOf(false) }
    var replyProxy by remember { mutableStateOf<JavaScriptReplyProxy?>(null) }
    var showQuickSignIn by remember { mutableStateOf(false) }
    val pendingOpens = remember { mutableStateListOf<NotificationDestination>() }
    var fileCallback by remember { mutableStateOf<ValueCallback<Array<Uri>>?>(null) }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        fileCallback?.onReceiveValue(uri?.let { arrayOf(it) })
        fileCallback = null
    }
    val supported = remember { WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) }

    fun post(proxy: JavaScriptReplyProxy?, message: String) {
        runCatching { proxy?.postMessage(message) }.onFailure { Log.w(TAG, "Bridge reply failed", it) }
    }

    fun issueHandoff(id: Int, proxy: JavaScriptReplyProxy) {
        scope.launch {
            try {
                val code = container.convex.action("appHandoff:issue", JSONObject()).optString("code")
                post(proxy, if (code.isBlank()) WebShellRules.handoffFailedMessage(id, retry = true) else WebShellRules.handoffMessage(id, code))
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (WebShellRules.isSessionEnded(error)) {
                    post(proxy, WebShellRules.handoffFailedMessage(id, retry = false))
                    onSignOut()
                } else {
                    Log.w(TAG, "Handoff failed", error)
                    post(proxy, WebShellRules.handoffFailedMessage(id, retry = true))
                }
            }
        }
    }

    fun receiveFile(json: JSONObject) {
        val save = json.optString("mode") == "save"
        scope.launch {
            val text = try {
                when (val result = files.receive(json.optString("name"), json.optString("mime"), json.optString("data"), save)) {
                    is WebFiles.Result.Opened -> if (result.savedToDownloads) "Đã lưu vào Tải xuống." else null
                    is WebFiles.Result.NoViewer ->
                        if (result.savedToDownloads) "Đã lưu vào Tải xuống. Máy chưa có ứng dụng mở được tệp này."
                        else "Máy chưa có ứng dụng mở được tệp này."
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.w(TAG, "File handoff failed", error)
                "Không mở được tệp. Vui lòng thử lại."
            }
            text?.let { Toast.makeText(context, it, Toast.LENGTH_LONG).show() }
        }
    }

    fun onBridgeMessage(text: String, proxy: JavaScriptReplyProxy) {
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return
        replyProxy = proxy
        when (json.optString("type")) {
            "ready" -> {
                // Never show another account's web session (left over in WebView storage).
                val webUserId = json.optString("userId")
                if (webUserId.isNotBlank() && webUserId != session.userId) {
                    post(proxy, JSONObject().put("type", "sign-out").toString())
                } else {
                    webReady = true
                    handoffFailed = false
                }
            }
            "handoff-request" -> issueHandoff(json.optInt("id"), proxy)
            "handoff-error" -> handoffFailed = true
            "signed-out" -> onSignOut()
            "quick-sign-in" -> showQuickSignIn = true
            "file" -> receiveFile(json)
        }
    }

    val webView = remember {
        WebView(context).apply {
            // MATCH_PARENT: with Compose's default WRAP_CONTENT the page's 100vh / 100dvh resolve to 0
            // (the web menu drawer collapsed to a strip).
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.setSupportMultipleWindows(false)
            settings.userAgentString = "${settings.userAgentString} LvtCrmApp/${BuildConfig.VERSION_NAME} (Android)"
            if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
                WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, false)
            }
            if (supported) {
                WebViewCompat.addWebMessageListener(this, WebShellRules.BRIDGE_NAME, setOf(origin)) { _, message, _, isMainFrame, proxy ->
                    if (isMainFrame) message.data?.let { onBridgeMessage(it, proxy) }
                }
            }
            webViewClient = object : WebViewClientCompat() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url.toString()
                    if (WebShellRules.isWebAppUrl(url, webUrl)) return false
                    if (WebShellRules.isExternalLink(url)) openOutside(context, request.url)
                    return true
                }

                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    webReady = false
                    loadFailed = false
                }

                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceErrorCompat) {
                    if (request.isForMainFrame) loadFailed = true
                }

                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                    if (request.isForMainFrame && errorResponse.statusCode >= 500) loadFailed = true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView,
                    filePathCallback: ValueCallback<Array<Uri>>,
                    fileChooserParams: FileChooserParams,
                ): Boolean {
                    fileCallback?.onReceiveValue(null)
                    fileCallback = filePathCallback
                    return try {
                        filePicker.launch(WebShellRules.pickerMimeTypes(fileChooserParams.acceptTypes))
                        true
                    } catch (_: ActivityNotFoundException) {
                        fileCallback = null
                        false
                    }
                }
            }
            setDownloadListener { url, _, _, _, _ ->
                if (WebShellRules.isExternalLink(url)) openOutside(context, Uri.parse(url))
            }
        }
    }

    DisposableEffect(webView) {
        if (supported) webView.loadUrl(webUrl)
        onDispose {
            fileCallback?.onReceiveValue(null)
            webView.destroy()
        }
    }

    // Connectivity: a banner while offline; a failed page reloads by itself when the network returns.
    DisposableEffect(Unit) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val main = Handler(Looper.getMainLooper())
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post {
                    online = true
                    if (loadFailed) webView.reload()
                }
            }

            override fun onLost(network: Network) {
                main.post { online = isOnline(context) }
            }
        }
        runCatching { manager?.registerDefaultNetworkCallback(callback) }
        onDispose { runCatching { manager?.unregisterNetworkCallback(callback) } }
    }

    // A tapped notification: the app marks it read, the web opens it like a bell item.
    LaunchedEffect(notificationDestination) {
        val destination = notificationDestination ?: return@LaunchedEffect
        pendingOpens.add(destination)
        destination.notificationKey?.let { key ->
            runCatching { container.notificationsRepository.markRead(key) }
                .onFailure { Log.w(TAG, "Mark-read failed", it) }
        }
        onNotificationDestinationHandled()
    }
    LaunchedEffect(webReady, replyProxy, pendingOpens.size) {
        val proxy = replyProxy ?: return@LaunchedEffect
        if (!webReady || pendingOpens.isEmpty()) return@LaunchedEffect
        pendingOpens.toList().forEach { post(proxy, WebShellRules.notificationMessage(it)) }
        pendingOpens.clear()
    }

    // Back: the web first closes an open menu / dialog (`__lvtAppBack`), then history, then leave.
    BackHandler {
        webView.evaluateJavascript("Boolean(window.__lvtAppBack && window.__lvtAppBack())") { handled ->
            if (handled == "true") return@evaluateJavascript
            if (webView.canGoBack()) webView.goBack() else context.findFragmentActivity()?.moveTaskToBack(true)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        AndroidView(factory = { webView }, modifier = Modifier.fillMaxSize())
        when {
            !supported -> MessageScreen(
                title = "Cần cập nhật Android System WebView",
                body = "Vào CH Play cập nhật Android System WebView rồi mở lại ứng dụng.",
                action = null,
            )
            loadFailed || handoffFailed -> MessageScreen(
                title = "Không có kết nối",
                body = if (online) "Không kết nối được máy chủ của trường. Vui lòng thử lại." else "Hãy bật Wi-Fi hoặc dữ liệu di động rồi thử lại.",
                action = "Thử lại" to {
                    loadFailed = false
                    handoffFailed = false
                    webView.reload()
                },
            )
            !online -> Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter)) {
                Text(
                    "Không có kết nối",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.padding(vertical = 6.dp),
                )
            }
        }
        if (showQuickSignIn) {
            QuickSignInSheet(
                userId = session.userId,
                email = session.email,
                name = session.name,
                deviceAuthRepository = container.deviceAuthRepository,
                onDismiss = { showQuickSignIn = false },
            )
        }
    }
}

/** Start without network (saved sign-in kept): retries by itself when the network returns. */
@Composable
fun OfflineStartScreen(onRetry: suspend () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    DisposableEffect(Unit) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        // Retry only when the network comes back: onAvailable also fires right after registering
        // while a network exists, which would loop against a server that is down.
        var wasOnline = isOnline(context)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val cameBack = !wasOnline
                wasOnline = true
                if (cameBack) scope.launch { onRetry() }
            }

            override fun onLost(network: Network) {
                wasOnline = isOnline(context)
            }
        }
        runCatching { manager?.registerDefaultNetworkCallback(callback) }
        onDispose { runCatching { manager?.unregisterNetworkCallback(callback) } }
    }
    MessageScreen(
        title = "Không có kết nối",
        body = "Chưa kết nối được máy chủ của trường. Kiểm tra Wi-Fi hoặc dữ liệu di động rồi bấm Thử lại; khi có mạng lại, ứng dụng tự mở.",
        action = "Thử lại" to { scope.launch { onRetry() }; Unit },
    )
}

@Composable
private fun MessageScreen(title: String, body: String, action: Pair<String, () -> Unit>?) {
    Surface(color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.fillMaxSize().padding(32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Icons.Outlined.CloudOff, contentDescription = null, modifier = Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            Text(body, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            action?.let { (label, onClick) -> Button(onClick = onClick) { Text(label) } }
        }
    }
}

private fun openOutside(context: Context, uri: Uri) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, "Máy chưa có ứng dụng mở được liên kết này.", Toast.LENGTH_SHORT).show()
    }
}

private fun isOnline(context: Context): Boolean {
    val manager = context.getSystemService(ConnectivityManager::class.java) ?: return true
    val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
    return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
}

/** Signing out (or another account signing in): nothing of the web session stays on the phone. */
object WebShellStorage {
    fun clear(context: Context) {
        runCatching { WebStorage.getInstance().deleteAllData() }
        runCatching {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        }
        // Private file responses may sit in the WebView HTTP cache.
        runCatching { WebView(context).apply { clearCache(true) }.destroy() }
        runCatching { WebFiles(context.applicationContext).clearCache() }
    }
}

private const val TAG = "LvtWebShell"
