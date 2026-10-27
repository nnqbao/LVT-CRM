package lvt.crm.ui.duties

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.PeopleOutline
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.TextButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.activity.compose.BackHandler
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import lvt.crm.data.chat.ChatKind
import lvt.crm.data.chat.ChatRepository
import lvt.crm.data.chat.ChatTarget
import lvt.crm.data.duties.DutyItem
import lvt.crm.ui.chat.ChatDialog
import lvt.crm.ui.components.IconTabBar
import lvt.crm.ui.components.IconTabItem
import lvt.crm.ui.components.ListSearchBar
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.components.StatusPill
import lvt.crm.ui.components.StatusTone
import lvt.crm.ui.components.GuideAnchors

@Composable
fun DutiesScreen(
    viewModel: DutiesViewModel,
    chatRepository: ChatRepository,
    focusId: String?,
    openChat: Boolean = false,
    focusToken: String? = null,
    tabOpenToken: Int,
    openTab: DutyListTab? = null,
    openFilterToken: Int = 0,
    onBackToHub: (() -> Unit)? = null,
) {
    val state by viewModel.uiState.collectAsState()
    val listState = rememberLazyListState()
    var selectedDutyId by remember { mutableStateOf<String?>(null) }
    var chatTarget by remember { mutableStateOf<ChatTarget?>(null) }
    var consumedChatToken by remember { mutableStateOf<String?>(null) }
    val selectedDuty = currentDuty(state.duties, selectedDutyId)

    LaunchedEffect(focusToken, openChat, focusId, state.loading, state.duties) {
        if (!openChat || focusId.isNullOrBlank() || focusToken.isNullOrBlank()) return@LaunchedEffect
        if (state.loading && state.duties.isEmpty()) return@LaunchedEffect
        if (consumedChatToken == focusToken) return@LaunchedEffect
        consumedChatToken = focusToken
        val duty = state.duties.firstOrNull { it.id == focusId }
        chatTarget = ChatTarget(
            ChatKind.Duty,
            focusId,
            duty?.let { dutyDisplayTitle(it) } ?: "Công tác",
        )
    }
    chatTarget?.let { target ->
        ChatDialog(
            repository = chatRepository,
            target = target,
            onBack = { chatTarget = null },
        )
    }

    BackHandler(enabled = selectedDutyId != null || onBackToHub != null) {
        if (selectedDutyId != null) selectedDutyId = null else onBackToHub?.invoke()
    }

    LaunchedEffect(selectedDutyId, selectedDuty) {
        if (selectedDutyId != null && selectedDuty == null && !state.loading) selectedDutyId = null
    }

    selectedDuty?.let { duty ->
        DutyDetailScreen(
            duty = duty,
            confirmationEnabled = state.attendanceConfirmationEnabled,
            busy = state.busyDutyId != null,
            actionError = state.actionError,
            onBack = { selectedDutyId = null },
            onAttend = { viewModel.setAttendance(duty.id, "attended") },
            onAbsent = { viewModel.setAttendance(duty.id, "absent") },
            onChat = {
                chatTarget = ChatTarget(ChatKind.Duty, duty.id, dutyDisplayTitle(duty))
            },
        )
        return
    }

    LaunchedEffect(focusId, state.duties) {
        if (!focusId.isNullOrBlank()) {
            val match = state.duties.firstOrNull { it.id == focusId }
            if (match != null) {
                selectedDutyId = match.id
                val tab = tabForDuty(match)
                if (isDutyAssignedTo(match)) viewModel.setMineTab(tab)
                if (isDutyCreatedBy(match, state.currentUserId) || !isDutyAssignedTo(match)) {
                    viewModel.setCreatedTab(tab)
                }
            }
        }
    }
    LaunchedEffect(tabOpenToken) {
        if (state.duties.isNotEmpty()) listState.scrollToItem(0)
    }
    LaunchedEffect(openFilterToken) {
        val tab = openTab ?: return@LaunchedEffect
        if (openFilterToken == 0) return@LaunchedEffect
        viewModel.applyListTab(tab)
        if (state.duties.isNotEmpty()) listState.scrollToItem(0)
    }

    LvtScreen(
        title = "Lịch công tác cá nhân",
        helpAnchor = GuideAnchors.DUTIES,
        refreshing = state.refreshing,
        onRefresh = { viewModel.refresh() },
        showAccountHeader = true,
        navigationIcon = onBackToHub?.let { back ->
            {
                IconButton(onClick = back) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
                }
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
        ) {
        when {
            state.loading -> {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator()
                    Text(
                        "Đang tải lịch công tác…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 14.dp),
                    )
                }
            }
            state.error != null -> {
                StatePanel(
                    icon = Icons.Outlined.WarningAmber,
                    title = "Chưa tải được công tác",
                    message = state.error.orEmpty(),
                    action = {
                        Button(onClick = { viewModel.refresh(initial = true) }) {
                            Text("Thử lại")
                        }
                    },
                )
            }
            else -> {
                state.actionError?.let {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer,
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 10.dp),
                    ) {
                        Text(
                            it,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(12.dp),
                        )
                    }
                }
                ListSearchBar(
                    value = state.search,
                    onChange = viewModel::updateSearch,
                    queryPlaceholder = "Tìm theo tên hoặc nội dung công tác",
                    personPlaceholder = "Tên người tham gia",
                    showLocation = true,
                    modifier = Modifier.padding(bottom = 12.dp),
                )
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    state = listState,
                    contentPadding = PaddingValues(bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item(key = "mine-heading") {
                        DutyListSectionHeader(
                            title = "Công tác của tôi",
                            tab = state.mineTab,
                            onTab = viewModel::setMineTab,
                        )
                    }
                    if (state.visibleMine.isEmpty()) {
                        item(key = "mine-empty") {
                            DutyListEmpty(
                                tab = state.mineTab,
                                created = false,
                                filtered = state.mineSearchEmpty,
                            )
                        }
                    } else {
                        items(state.visibleMine, key = { "mine-${it.id}" }) { duty ->
                            DutyCard(
                                duty = duty,
                                focused = duty.id == focusId,
                                confirmationEnabled = state.attendanceConfirmationEnabled,
                                busy = state.busyDutyId != null,
                                onOpen = { selectedDutyId = duty.id },
                                onAttend = { viewModel.setAttendance(duty.id, "attended") },
                                onAbsent = { viewModel.setAttendance(duty.id, "absent") },
                                onChat = {
                                    chatTarget = ChatTarget(ChatKind.Duty, duty.id, dutyDisplayTitle(duty))
                                },
                            )
                        }
                    }
                    if (state.showCreatedSection) {
                        item(key = "created-heading") {
                            Spacer(modifier = Modifier.height(36.dp))
                            DutyListSectionHeader(
                                title = "Công tác tôi tạo",
                                tab = state.createdTab,
                                onTab = viewModel::setCreatedTab,
                            )
                        }
                        if (state.visibleCreated.isEmpty()) {
                            item(key = "created-empty") {
                                DutyListEmpty(
                                    tab = state.createdTab,
                                    created = true,
                                    filtered = state.createdSearchEmpty,
                                )
                            }
                        } else {
                            items(state.visibleCreated, key = { "created-${it.id}" }) { duty ->
                                DutyCard(
                                    duty = duty,
                                    focused = duty.id == focusId,
                                    confirmationEnabled = state.attendanceConfirmationEnabled,
                                    busy = state.busyDutyId != null,
                                    onOpen = { selectedDutyId = duty.id },
                                    onAttend = { viewModel.setAttendance(duty.id, "attended") },
                                    onAbsent = { viewModel.setAttendance(duty.id, "absent") },
                                    onChat = {
                                        chatTarget = ChatTarget(ChatKind.Duty, duty.id, dutyDisplayTitle(duty))
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
        }
    }
}

internal fun currentDuty(duties: List<DutyItem>, selectedDutyId: String?): DutyItem? =
    duties.firstOrNull { it.id == selectedDutyId }

@Composable
private fun DutyListSectionHeader(
    title: String,
    tab: DutyListTab,
    onTab: (DutyListTab) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        IconTabBar(
            items = DutyListTab.entries.map { IconTabItem(it.title, it.icon) },
            selectedIndex = tab.ordinal,
            onSelect = { index -> onTab(DutyListTab.entries[index]) },
        )
    }
}

private val DutyListTab.icon: ImageVector
    get() = when (this) {
        DutyListTab.Upcoming -> Icons.Outlined.Schedule
        DutyListTab.Ongoing -> Icons.Outlined.PlayCircle
        DutyListTab.Past -> Icons.Outlined.CheckCircle
    }

@Composable
private fun DutyListEmpty(tab: DutyListTab, created: Boolean, filtered: Boolean = false) {
    val message = when {
        filtered -> "Không tìm thấy công tác phù hợp."
        tab == DutyListTab.Past -> if (created) "Chưa có công tác bạn tạo đã diễn ra." else "Chưa có sự kiện đã diễn ra."
        tab == DutyListTab.Ongoing -> if (created) "Chưa có công tác bạn tạo đang diễn ra." else "Chưa có sự kiện đang diễn ra."
        else -> if (created) "Chưa có công tác bạn tạo sắp diễn ra." else "Chưa có sự kiện sắp diễn ra."
    }
    StatePanel(
        icon = if (filtered) Icons.Outlined.Search else Icons.Outlined.EventBusy,
        title = if (created) "Công tác tôi tạo" else "Công tác của tôi",
        message = message,
    )
}

@Composable
private fun DutyCard(
    duty: DutyItem,
    focused: Boolean,
    confirmationEnabled: Boolean,
    busy: Boolean,
    onOpen: () -> Unit,
    onAttend: () -> Unit,
    onAbsent: () -> Unit,
    onChat: () -> Unit,
) {
    val cardModifier = if (focused) {
        Modifier
            .fillMaxWidth()
            .border(
                width = 2.dp,
                color = MaterialTheme.colorScheme.primary,
                shape = MaterialTheme.shapes.medium,
            )
    } else {
        Modifier.fillMaxWidth()
    }
    Card(
        modifier = cardModifier,
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = if (focused) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.48f)
            } else {
                MaterialTheme.colorScheme.surface
            },
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(
            modifier = Modifier
                .clickable(onClick = onOpen)
                .padding(17.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Text(
                    dutyDisplayTitle(duty).truncateCharacters(50),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Spacer(modifier = Modifier.width(8.dp))
                StatusPill(
                    label = timingLabel(duty),
                    tone = timingTone(duty),
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            DetailLine(
                icon = Icons.Outlined.CalendarMonth,
                text = scheduleLabel(duty),
            )
            if (duty.locationNames.isNotEmpty()) {
                DetailLine(
                    icon = Icons.Outlined.LocationOn,
                    text = duty.locationNames.joinToString(", "),
                )
            }
            if (duty.departmentNames.isNotEmpty()) {
                DetailLine(
                    icon = Icons.Outlined.Groups,
                    text = duty.departmentNames.joinToString(", "),
                )
            }
            if (confirmationEnabled && duty.isMine && duty.canMarkAttendance) {
                Spacer(modifier = Modifier.height(15.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Button(
                        onClick = onAttend,
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                        Text("Có mặt", modifier = Modifier.padding(start = 6.dp))
                    }
                    FilledTonalButton(
                        onClick = onAbsent,
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Outlined.Cancel, contentDescription = null)
                        Text("Vắng", modifier = Modifier.padding(start = 6.dp))
                    }
                }
            }
            TextButton(onClick = onChat, modifier = Modifier.padding(top = 4.dp)) {
                Text("Trao đổi")
            }
        }
    }
}

@Composable
private fun DutyDetailScreen(
    duty: DutyItem,
    confirmationEnabled: Boolean,
    busy: Boolean,
    actionError: String?,
    onBack: () -> Unit,
    onAttend: () -> Unit,
    onAbsent: () -> Unit,
    onChat: () -> Unit,
) {
    LvtScreen(
        title = "Chi tiết công tác",
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại danh sách công tác")
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
        ) {
        actionError?.let {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
            ) {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(12.dp),
                )
            }
        }
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        ) {
            Column(modifier = Modifier.padding(18.dp)) {
                Text(dutyDisplayTitle(duty), style = MaterialTheme.typography.headlineSmall)
                Spacer(modifier = Modifier.height(18.dp))
                DetailLine(Icons.Outlined.CalendarMonth, "Ngày giờ công tác: ${scheduleLabel(duty)}")
                DetailLine(
                    Icons.Outlined.LocationOn,
                    "Địa điểm: ${duty.locationNames.ifEmpty { listOf("Chưa cập nhật") }.joinToString(", ")}",
                )
                DetailLine(
                    Icons.Outlined.Groups,
                    "Phòng ban tham gia: ${duty.departmentNames.ifEmpty { listOf("Chưa cập nhật") }.joinToString(", ")}",
                )
                duty.departmentParticipants.forEach { department ->
                    DetailLine(
                        Icons.Outlined.PeopleOutline,
                        "${department.departmentName}: ${department.participantNames.ifEmpty { listOf("Chưa cập nhật cá nhân") }.joinToString(", ")}",
                    )
                }
                if (duty.participantNames.isNotEmpty() || duty.otherParticipants.isBlank()) {
                    DetailLine(
                        Icons.Outlined.PeopleOutline,
                        "Cá nhân tham gia: ${duty.participantNames.ifEmpty { listOf("Chưa cập nhật") }.joinToString(", ")}",
                    )
                }
                if (duty.otherParticipants.isNotBlank()) {
                    DetailLine(
                        Icons.Outlined.PeopleOutline,
                        "Thành phần khác: ${duty.otherParticipants}",
                    )
                }
                if (confirmationEnabled && duty.isMine) {
                    Spacer(modifier = Modifier.height(18.dp))
                    StatusPill(label = statusLabel(duty.myStatus), tone = statusTone(duty.myStatus))
                    if (duty.canMarkAttendance) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Button(onClick = onAttend, enabled = !busy, modifier = Modifier.weight(1f)) {
                                Text("Có mặt")
                            }
                            FilledTonalButton(onClick = onAbsent, enabled = !busy, modifier = Modifier.weight(1f)) {
                                Text("Vắng")
                            }
                        }
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))
                Button(onClick = onChat, modifier = Modifier.fillMaxWidth()) {
                    Text("Trao đổi")
                }
            }
        }
        }
    }
}

@Composable
private fun DetailLine(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
) {
    Row(
        modifier = Modifier.padding(vertical = 3.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
    }
}

private fun scheduleLabel(duty: DutyItem): String {
    val date = if (duty.startDate == duty.endDate) {
        duty.startDate
    } else {
        "${duty.startDate} → ${duty.endDate}"
    }
    val time = if (duty.allDay) "Cả ngày" else "${duty.startTime}–${duty.endTime}"
    return "$date · $time"
}

private fun statusLabel(status: String): String = when (status) {
    "attended" -> "Đã xác nhận có mặt"
    "absent" -> "Đã báo vắng"
    "pending" -> "Chưa xác nhận"
    else -> status
}

private fun statusTone(status: String): StatusTone = when (status) {
    "attended" -> StatusTone.Positive
    "absent" -> StatusTone.Warning
    else -> StatusTone.Neutral
}

private fun timingLabel(duty: DutyItem): String = when {
    duty.isOngoing -> "Đang diễn ra"
    duty.isOverdue -> "Đã kết thúc"
    duty.isUpcoming -> "Sắp tới"
    else -> "Theo lịch"
}

private fun timingTone(duty: DutyItem): StatusTone = when {
    duty.isOngoing -> StatusTone.Positive
    duty.isOverdue -> StatusTone.Neutral
    duty.isUpcoming -> StatusTone.Primary
    else -> StatusTone.Neutral
}

private fun String.truncateCharacters(limit: Int): String {
    val normalized = trim()
    return if (normalized.length > limit) normalized.take(limit).trimEnd() + "…" else normalized
}
