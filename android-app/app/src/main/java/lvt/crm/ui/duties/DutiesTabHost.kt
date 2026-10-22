package lvt.crm.ui.duties

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import lvt.crm.data.chat.ChatRepository
import lvt.crm.data.duties.DutiesRepository
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.GuideAnchors

private enum class DutiesTabPage { Hub, Personal, SharedPicker }

@Composable
fun DutiesTabHost(
    viewModel: DutiesViewModel,
    dutiesRepository: DutiesRepository,
    chatRepository: ChatRepository,
    focusId: String?,
    openChat: Boolean = false,
    focusToken: String? = null,
    tabOpenToken: Int,
    openTab: DutyListTab? = null,
    openFilterToken: Int = 0,
    skipHub: Boolean = false,
    /** Monday of a week to open on Lịch công tác chung (from an approval notification). */
    openWeek: String? = null,
) {
    fun startPage() = when {
        !openWeek.isNullOrBlank() -> DutiesTabPage.SharedPicker
        skipHub || !focusId.isNullOrBlank() -> DutiesTabPage.Personal
        else -> DutiesTabPage.Hub
    }
    var page by remember { mutableStateOf(startPage()) }
    LaunchedEffect(tabOpenToken, skipHub, focusId, openWeek, focusToken) {
        page = startPage()
    }

    when (page) {
        DutiesTabPage.Hub -> DutiesHubScreen(
            onOpenPersonal = { page = DutiesTabPage.Personal },
            onOpenShared = { page = DutiesTabPage.SharedPicker },
        )
        DutiesTabPage.Personal -> DutiesScreen(
            viewModel = viewModel,
            chatRepository = chatRepository,
            focusId = focusId,
            openChat = openChat,
            focusToken = focusToken,
            tabOpenToken = tabOpenToken,
            openTab = openTab,
            openFilterToken = openFilterToken,
            onBackToHub = if (skipHub) null else ({ page = DutiesTabPage.Hub }),
        )
        DutiesTabPage.SharedPicker -> SharedWeekScreen(
            dutiesRepository = dutiesRepository,
            initialWeekStart = openWeek,
            openToken = focusToken,
            onBack = { page = DutiesTabPage.Hub },
        )
    }
}

@Composable
fun DutiesHubScreen(
    onOpenPersonal: () -> Unit,
    onOpenShared: () -> Unit,
) {
    LvtScreen(title = "Lịch CT", showAccountHeader = true, helpAnchor = GuideAnchors.DUTIES) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                HubChoiceCard(
                    title = "Lịch công tác cá nhân",
                    subtitle = "Công tác được giao và công tác bạn tạo",
                    icon = { Icon(Icons.Outlined.Person, contentDescription = null, modifier = Modifier.size(32.dp)) },
                    onClick = onOpenPersonal,
                )
                HubChoiceCard(
                    title = "Lịch công tác chung",
                    subtitle = "Lịch tuần toàn trường đã duyệt, duyệt lịch và tải PDF",
                    icon = { Icon(Icons.Outlined.CalendarMonth, contentDescription = null, modifier = Modifier.size(32.dp)) },
                    onClick = onOpenShared,
                )
            }
        }
    }
}

@Composable
private fun HubChoiceCard(
    title: String,
    subtitle: String,
    icon: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    ElevatedCard(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 132.dp),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 2.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            icon()
            Spacer(modifier = Modifier.height(10.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
