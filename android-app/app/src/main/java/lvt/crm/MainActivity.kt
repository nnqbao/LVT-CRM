package lvt.crm

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.flow.MutableStateFlow
import lvt.crm.push.NotificationDestination
import lvt.crm.ui.LvtRoot
import lvt.crm.ui.theme.LvtCrmTheme
import lvt.crm.update.PlayStoreUpdater

/** FragmentActivity (still a ComponentActivity) so BiometricPrompt can host its fragment. */
class MainActivity : FragmentActivity() {
    private data class PendingDestination(val id: Long, val destination: NotificationDestination)

    private val destinationQueue = ArrayDeque<PendingDestination>()
    private val pendingDestination = MutableStateFlow<PendingDestination?>(null)
    private var nextDestinationId = 1L
    private val playUpdateLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { /* Immediate update: retry on the next resume if the user backs out. */ }
    private lateinit var playStoreUpdater: PlayStoreUpdater

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        playStoreUpdater = PlayStoreUpdater(this, playUpdateLauncher)
        enableEdgeToEdge()
        restorePendingDestinations(savedInstanceState).forEach(::enqueueDestination)
        if (savedInstanceState == null) {
            acceptNotificationIntent(intent)?.let(::enqueueDestination)
        }
        val container = (application as LvtApplication).container
        setContent {
            val pending by pendingDestination.collectAsState()
            val appearance by container.appearanceStore.mode.collectAsState()
            LvtCrmTheme(appearanceMode = appearance) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    LvtRoot(
                        container = container,
                        notificationDestination = pending?.destination,
                        onNotificationDestinationHandled = {
                            pending?.let { acknowledgeDestination(it.id) }
                        },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        playStoreUpdater.checkOnResume()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptNotificationIntent(intent)?.let(::enqueueDestination)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (destinationQueue.isNotEmpty()) {
            outState.putLongArray(STATE_IDS, destinationQueue.map { it.id }.toLongArray())
            outState.putStringArrayList(STATE_KINDS, ArrayList(destinationQueue.map { it.destination.kind }))
            outState.putStringArrayList(STATE_SOURCE_TYPES, ArrayList(destinationQueue.map { it.destination.sourceType }))
            outState.putStringArrayList(STATE_SOURCE_IDS, ArrayList(destinationQueue.map { it.destination.sourceId }))
            outState.putStringArrayList(
                STATE_NOTIFICATION_KEYS,
                ArrayList(destinationQueue.map { it.destination.notificationKey.orEmpty() }),
            )
        }
        super.onSaveInstanceState(outState)
    }

    private fun acceptNotificationIntent(intent: Intent): PendingDestination? {
        val destination = NotificationDestination.fromIntent(intent) ?: return null
        intent.removeExtra(NotificationDestination.EXTRA_KIND)
        intent.removeExtra(NotificationDestination.EXTRA_SOURCE_TYPE)
        intent.removeExtra(NotificationDestination.EXTRA_SOURCE_ID)
        intent.removeExtra(NotificationDestination.EXTRA_NOTIFICATION_KEY)
        if (intent.data?.scheme == "lvtcrm" && intent.data?.host == "notification") intent.data = null
        return PendingDestination(nextDestinationId++, destination)
    }

    private fun restorePendingDestinations(state: Bundle?): List<PendingDestination> {
        val ids = state?.getLongArray(STATE_IDS) ?: return emptyList()
        val kinds = state.getStringArrayList(STATE_KINDS).orEmpty()
        val sourceTypes = state.getStringArrayList(STATE_SOURCE_TYPES).orEmpty()
        val sourceIds = state.getStringArrayList(STATE_SOURCE_IDS).orEmpty()
        val notificationKeys = state.getStringArrayList(STATE_NOTIFICATION_KEYS).orEmpty()
        return ids.indices.mapNotNull { index ->
            val sourceId = sourceIds.getOrNull(index)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val id = ids[index]
            nextDestinationId = maxOf(nextDestinationId, id + 1)
            PendingDestination(
                id,
                NotificationDestination(
                    kind = kinds.getOrNull(index).orEmpty(),
                    sourceType = sourceTypes.getOrNull(index).orEmpty(),
                    sourceId = sourceId,
                    notificationKey = notificationKeys.getOrNull(index)?.takeIf { it.isNotBlank() },
                ),
            )
        }
    }

    private fun acknowledgeDestination(id: Long) {
        if (destinationQueue.firstOrNull()?.id != id) return
        destinationQueue.removeFirst()
        pendingDestination.value = destinationQueue.firstOrNull()
    }

    private fun enqueueDestination(pending: PendingDestination) {
        destinationQueue.addLast(pending)
        if (pendingDestination.value == null) pendingDestination.value = pending
    }

    companion object {
        private const val STATE_IDS = "lvt.pending_notification.ids"
        private const val STATE_KINDS = "lvt.pending_notification.kinds"
        private const val STATE_SOURCE_TYPES = "lvt.pending_notification.source_types"
        private const val STATE_SOURCE_IDS = "lvt.pending_notification.source_ids"
        private const val STATE_NOTIFICATION_KEYS = "lvt.pending_notification.keys"
    }
}
