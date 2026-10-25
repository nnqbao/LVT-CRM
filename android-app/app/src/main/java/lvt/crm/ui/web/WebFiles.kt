package lvt.crm.ui.web

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import androidx.core.content.FileProvider
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Files the web hands over (`{ type: 'file' }`): a WebView cannot save `blob:` downloads or show
 * PDFs itself. `open` keeps the file in the app cache (replaced on the next file); `save` also
 * stores it in Downloads (Android 10+). Either way the phone's viewer opens it.
 */
class WebFiles(private val context: Context) {
    sealed interface Result {
        data class Opened(val savedToDownloads: Boolean) : Result
        data class NoViewer(val savedToDownloads: Boolean) : Result
    }

    suspend fun receive(name: String, claimedMime: String, base64: String, save: Boolean): Result {
        val fileName = WebShellRules.safeFileName(name)
        val mime = WebShellRules.mimeFor(fileName, claimedMime)
        val uri = withContext(Dispatchers.IO) {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            require(bytes.isNotEmpty()) { "EMPTY_FILE" }
            if (save && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) saveToDownloads(fileName, mime, bytes) else cacheFile(fileName, bytes)
        }
        val saved = save && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(Intent.createChooser(intent, fileName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            Result.Opened(saved)
        } catch (_: ActivityNotFoundException) {
            Result.NoViewer(saved)
        }
    }

    private fun cacheFile(fileName: String, bytes: ByteArray): Uri {
        val dir = File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, fileName)
        val staged = File(dir, "$fileName.part")
        staged.writeBytes(bytes)
        if (!staged.renameTo(file)) {
            staged.delete()
            error("FILE_WRITE_FAILED")
        }
        return FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    private fun saveToDownloads(fileName: String, mime: String, bytes: ByteArray): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("FILE_WRITE_FAILED")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("FILE_WRITE_FAILED")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
        return uri
    }

    /** Signing out: nothing the web handed over stays in the app cache. */
    fun clearCache() {
        File(context.cacheDir, CACHE_DIR).deleteRecursively()
    }

    private companion object {
        /** Listed in res/xml/file_paths.xml. */
        const val CACHE_DIR = "web-files"
    }
}
