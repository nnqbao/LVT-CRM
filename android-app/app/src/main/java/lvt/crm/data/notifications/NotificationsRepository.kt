package lvt.crm.data.notifications

import lvt.crm.data.convex.ConvexHttpClient
import org.json.JSONArray
import org.json.JSONObject

data class NotificationItem(
    val key: String,
    val kind: String,
    val sourceType: String,
    val sourceId: String,
    val title: String,
    val description: String,
    val dueAt: Long,
    val milestoneHours: Int,
    val milestoneLabel: String,
    val read: Boolean,
    /** Web menu a kind `people` item opens (`staff-faults` / `people-review`); empty otherwise. */
    val menu: String = "",
)

data class NotificationSettings(
    val dutiesEnabled: Boolean,
    val workEnabled: Boolean,
    val milestonesHours: List<Int>,
)

data class NotificationsSnapshot(
    val items: List<NotificationItem>,
    val unreadCount: Int,
    val canDelete: Boolean,
    val settings: NotificationSettings,
)

class NotificationsRepository(
    private val convex: ConvexHttpClient,
) {
    suspend fun feed(now: Long = System.currentTimeMillis()): NotificationsSnapshot {
        val result = convex.query(
            "notifications:feed",
            JSONObject().put("now", now),
        )
        val items = buildList {
            val array = result.optJSONArray("items") ?: JSONArray()
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val key = item.optString("key")
                val sourceId = item.optString("sourceId")
                if (key.isBlank() || sourceId.isBlank()) continue
                add(
                    NotificationItem(
                        key = key,
                        kind = item.optString("kind"),
                        sourceType = item.optString("sourceType"),
                        sourceId = sourceId,
                        title = item.optString("title"),
                        description = item.optString("description"),
                        dueAt = item.optLong("dueAt"),
                        milestoneHours = item.optInt("milestoneHours"),
                        milestoneLabel = item.optString("milestoneLabel"),
                        read = item.optBoolean("read", false),
                        menu = item.optString("menu"),
                    ),
                )
            }
        }
        val settings = result.optJSONObject("settings") ?: JSONObject()
        return NotificationsSnapshot(
            items = items,
            unreadCount = result.optInt("unreadCount", items.count { !it.read }),
            canDelete = result.optBoolean("canDelete", false),
            settings = NotificationSettings(
                dutiesEnabled = settings.optBoolean("dutiesEnabled", true),
                workEnabled = settings.optBoolean("workEnabled", true),
                milestonesHours = settings.optJSONArray("milestonesHours").toIntList(),
            ),
        )
    }

    suspend fun markRead(notificationKey: String) {
        convex.mutation(
            "notifications:markRead",
            JSONObject().put("notificationKey", notificationKey),
        )
    }

    suspend fun markAllRead(notificationKeys: List<String>) {
        convex.mutation(
            "notifications:markAllRead",
            JSONObject().put("notificationKeys", JSONArray(notificationKeys)),
        )
    }

    suspend fun dismiss(notificationKey: String) {
        convex.mutation(
            "notifications:dismiss",
            JSONObject().put("notificationKey", notificationKey),
        )
    }
}

private fun JSONArray?.toIntList(): List<Int> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            add(optInt(index))
        }
    }
}
