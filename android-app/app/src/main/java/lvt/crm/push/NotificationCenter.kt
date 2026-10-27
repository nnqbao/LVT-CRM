package lvt.crm.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import lvt.crm.MainActivity
import lvt.crm.R
import lvt.crm.data.notifications.NotificationItem

object NotificationCenter {
    const val CHANNEL_ID = "lvt_crm_deadlines"
    private const val GROUP_KEY = "lvt_crm_notifications"

    fun createChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Công tác và công việc",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Nhắc công tác, công việc gần đến hạn và kết quả bị từ chối."
        }
        manager.createNotificationChannel(channel)
    }

    fun show(context: Context, item: NotificationItem): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false

        val destinationIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            data = NotificationDestination.toUri(
                NotificationDestination(
                    kind = item.kind,
                    sourceType = item.sourceType,
                    sourceId = item.sourceId,
                    notificationKey = item.key,
                    menu = item.menu,
                ),
            )
            putExtra(NotificationDestination.EXTRA_KIND, item.kind)
            putExtra(NotificationDestination.EXTRA_SOURCE_TYPE, item.sourceType)
            putExtra(NotificationDestination.EXTRA_SOURCE_ID, item.sourceId)
            putExtra(NotificationDestination.EXTRA_NOTIFICATION_KEY, item.key)
            putExtra(NotificationDestination.EXTRA_MENU, item.menu)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            item.key.hashCode(),
            destinationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = NotificationPresentation.systemTitle(item.kind, item.sourceType, item.milestoneLabel)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(item.title)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    listOf(item.title, item.description)
                        .filter { it.isNotBlank() }
                        .joinToString("\n"),
                ),
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP_KEY)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
        manager.notify(item.key.hashCode(), notification)
        return true
    }
}
