package lvt.crm.push

import android.content.Intent
import android.net.Uri

data class NotificationDestination(
    val kind: String,
    val sourceType: String,
    val sourceId: String,
    val notificationKey: String?,
) {
    val route: String
        get() = if (opensChat) "chat" else routeForKind(kind)

    /** Bell items for Trao đổi open the chat hub. Other kinds still select their tab. */
    val opensChat: Boolean
        get() = opensChat(sourceType)

    /** "Việc của tôi" reminders (kind `todo`, sourceType `todo_reminder`) open the todo list under Công việc. */
    val opensTodos: Boolean
        get() = !opensChat && isTodo(kind, sourceType)

    val chatKind: String
        get() = when (sourceType) {
            "duty_chat" -> "duty"
            "group_chat" -> "group"
            else -> "work"
        }

    companion object {
        const val EXTRA_KIND = "lvt.notification.kind"
        const val EXTRA_SOURCE_TYPE = "lvt.notification.source_type"
        const val EXTRA_SOURCE_ID = "lvt.notification.source_id"
        const val EXTRA_NOTIFICATION_KEY = "lvt.notification.key"

        fun fromIntent(intent: Intent?): NotificationDestination? {
            val data = intent?.data?.takeIf {
                it.scheme == DEEP_LINK_SCHEME && it.host == DEEP_LINK_HOST
            }
            val sourceId = (
                intent?.getStringExtra(EXTRA_SOURCE_ID)
                    ?: data?.getQueryParameter(QUERY_SOURCE_ID)
                )?.takeIf { it.isNotBlank() } ?: return null
            return NotificationDestination(
                kind = intent?.getStringExtra(EXTRA_KIND)
                    ?: data?.getQueryParameter(QUERY_KIND).orEmpty(),
                sourceType = intent?.getStringExtra(EXTRA_SOURCE_TYPE)
                    ?: data?.getQueryParameter(QUERY_SOURCE_TYPE).orEmpty(),
                sourceId = sourceId,
                notificationKey = intent?.getStringExtra(EXTRA_NOTIFICATION_KEY)
                    ?: data?.getQueryParameter(QUERY_NOTIFICATION_KEY),
            )
        }

        fun toUri(destination: NotificationDestination): Uri =
            Uri.Builder()
                .scheme(DEEP_LINK_SCHEME)
                .authority(DEEP_LINK_HOST)
                .appendQueryParameter(QUERY_KIND, destination.kind)
                .appendQueryParameter(QUERY_SOURCE_TYPE, destination.sourceType)
                .appendQueryParameter(QUERY_SOURCE_ID, destination.sourceId)
                .apply {
                    destination.notificationKey?.let {
                        appendQueryParameter(QUERY_NOTIFICATION_KEY, it)
                    }
                }
                .build()

        /** Duty items open Lịch công tác; work items and todo reminders open the Công việc hub. */
        fun routeForKind(kind: String): String =
            if (kind == "duty") "duties" else "work"

        fun isTodo(kind: String, sourceType: String): Boolean =
            kind == "todo" || sourceType == "todo_reminder"

        fun opensChat(sourceType: String): Boolean =
            sourceType == "duty_chat" || sourceType == "work_chat" || sourceType == "group_chat"

        private const val DEEP_LINK_SCHEME = "lvtcrm"
        private const val DEEP_LINK_HOST = "notification"
        private const val QUERY_KIND = "kind"
        private const val QUERY_SOURCE_TYPE = "sourceType"
        private const val QUERY_SOURCE_ID = "sourceId"
        private const val QUERY_NOTIFICATION_KEY = "key"
    }
}
