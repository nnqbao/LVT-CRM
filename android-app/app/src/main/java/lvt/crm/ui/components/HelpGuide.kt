package lvt.crm.ui.components

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import lvt.crm.data.convex.ConvexConfig

/**
 * Anchors of the user guide (`/huong-dan-su-dung.html`), copied from the web
 * `GUIDE_ANCHORS` in `src/navigationRoutes.js`. Keep in sync when the guide changes.
 */
object GuideAnchors {
    const val REPORTS = "menu-bao-cao"
    const val NOTIFICATIONS = "tb-thong-bao"
    const val CHAT = "td-trao-doi"
    const val DUTIES = "menu-lich-cong-tac"
    const val WORK = "menu-cong-viec"
    const val HOMEROOM = "menu-lop-chu-nhiem"
    const val ATTENDANCE = "menu-diem-danh"
    const val BOARDING = "bt-ban-tru"
    const val PROFILE = "tai-khoan-ca-nhan"
    const val CHANGE_PASSWORD = "doi-mat-khau"
    const val DEVICES = "thiet-bi-dang-nhap"

    /** The app's Tổng quan has no web menu; it opens the guide's quick start section. */
    const val OVERVIEW = "bat-dau-nhanh"
}

object HelpGuide {
    const val GUIDE_PATH = "/huong-dan-su-dung.html"

    /** Compact guide (no hero, sidebar or search) showing only that topic, like the web's guideEmbedUrl. */
    fun embedUrl(webBaseUrl: String, anchor: String?): String {
        val base = webBaseUrl.trim().trimEnd('/')
        val hash = anchor?.trim()?.takeIf { it.isNotEmpty() }?.let { "#$it" }.orEmpty()
        return "$base$GUIDE_PATH?embed=1$hash"
    }

    /**
     * Opens the guide in a Custom Tab when the browser supports it (protocol extra, no library
     * needed), otherwise in any browser. Never throws.
     */
    fun open(context: Context, anchor: String?, webBaseUrl: String = ConvexConfig.webUrl) {
        WebPage.open(context, embedUrl(webBaseUrl, anchor))
    }
}

/** A page of the web app (e.g. Ghi nhận lỗi, which has no app screen), opened like the guide. */
object WebPage {
    fun url(path: String, webBaseUrl: String = ConvexConfig.webUrl): String =
        "${webBaseUrl.trim().trimEnd('/')}/${path.trimStart('/')}"

    fun open(context: Context, url: String) {
        val uri = Uri.parse(url)
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            // Custom Tabs protocol: a session extra (null binder is allowed) asks the browser
            // to show the page as a Custom Tab; browsers without support ignore it.
            putExtras(Bundle().apply { putBinder(EXTRA_CUSTOM_TABS_SESSION, null) })
            if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (error: ActivityNotFoundException) {
            Log.w("LvtHelp", "No browser to open the web page", error)
        } catch (error: SecurityException) {
            Log.w("LvtHelp", "Web page intent rejected", error)
        }
    }

    private const val EXTRA_CUSTOM_TABS_SESSION = "android.support.customtabs.extra.SESSION"
}

/** "?" action of a main screen's top bar. */
@Composable
fun HelpGuideButton(anchor: String) {
    val context = LocalContext.current
    IconButton(onClick = { HelpGuide.open(context, anchor) }) {
        Icon(Icons.AutoMirrored.Outlined.HelpOutline, contentDescription = "Hướng dẫn sử dụng")
    }
}
