package lvt.crm.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.WorkOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import lvt.crm.data.chat.CHAT_RECALLED_PLACEHOLDER
import lvt.crm.data.chat.ChatConversation
import lvt.crm.data.chat.ChatGroupState
import lvt.crm.data.chat.ChatInboxSnapshot
import lvt.crm.data.chat.ChatKind
import lvt.crm.data.chat.ChatPerson
import lvt.crm.data.chat.ChatRepository
import lvt.crm.data.chat.ChatTarget
import lvt.crm.data.chat.chatHubFailureMessage
import lvt.crm.data.chat.chatKindFromWire
import lvt.crm.data.chat.chatKindLabel
import lvt.crm.data.chat.chatListPreview
import lvt.crm.data.chat.chatSearchMatch
import lvt.crm.data.chat.chatThreadKey
import lvt.crm.data.chat.formatChatListTime
import lvt.crm.data.convex.ConvexException
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.GuideAnchors

private const val POLL_MS = 8_000L
private val FILTERS = listOf(
    null to "Tất cả",
    ChatKind.Duty to "Công tác",
    ChatKind.Work to "Công việc",
    ChatKind.Group to "Nhóm",
)

@Composable
fun ChatHubScreen(
    repository: ChatRepository,
    openKind: String?,
    openEntityId: String?,
    openToken: String?,
    onOpenWork: (String) -> Unit,
    onOpenDuty: (String) -> Unit,
    onUnread: (Int) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var inbox by remember { mutableStateOf<ChatInboxSnapshot?>(null) }
    var loading by remember { mutableStateOf(true) }
    var refreshing by remember { mutableStateOf(false) }
    var listError by remember { mutableStateOf<String?>(null) }
    var filter by remember { mutableStateOf<ChatKind?>(null) }
    var search by remember { mutableStateOf("") }
    var opened by remember { mutableStateOf<ChatConversation?>(null) }
    var creating by remember { mutableStateOf(false) }
    var managing by remember { mutableStateOf(false) }

    suspend fun refreshInbox() {
        runCatching { repository.inbox() }
            .onSuccess { snapshot ->
                inbox = snapshot
                listError = null
                val unread = runCatching { repository.unreadTotal() }.getOrDefault(
                    snapshot.conversations.sumOf { it.unreadCount },
                )
                onUnread(unread)
            }
            .onFailure { failure ->
                if (inbox == null) listError = failure.hubMessage()
            }
        loading = false
        refreshing = false
    }

    LaunchedEffect(Unit) {
        while (true) {
            refreshInbox()
            delay(POLL_MS)
        }
    }
    LaunchedEffect(inbox?.backfillPending == true) {
        if (inbox?.backfillPending != true) return@LaunchedEffect
        while (true) {
            var steps = 0
            var done = false
            while (steps < 40 && !done) {
                steps += 1
                done = runCatching { repository.continueBackfill() }.getOrDefault(false)
                if (!done) delay(60)
            }
            refreshInbox()
            if (done || inbox?.backfillPending != true) break
            delay(POLL_MS)
        }
    }
    LaunchedEffect(openToken) {
        val kind = chatKindFromWire(openKind.orEmpty()) ?: return@LaunchedEffect
        val entityId = openEntityId?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        if (openToken.isNullOrBlank()) return@LaunchedEffect
        val existing = inbox?.conversations?.firstOrNull { it.kind == kind && it.entityId == entityId }
        opened = existing ?: placeholderConversation(kind, entityId)
    }

    val thread = opened
    if (thread != null) {
        Box(modifier = Modifier.fillMaxSize()) {
        ChatThreadHost(
            repository = repository,
            conversation = thread,
            onBack = { opened = null },
            onOpenWork = onOpenWork,
            onOpenDuty = onOpenDuty,
            onManage = { managing = true },
            onArchive = {
                scope.launch {
                    runCatching { repository.archiveMine(thread.threadKey) }
                    opened = null
                    refreshInbox()
                }
            },
        )
        if (managing && thread.kind == ChatKind.Group) {
            ManageGroupScreen(
                repository = repository,
                groupId = thread.entityId,
                onClose = { managing = false },
                onLeft = {
                    managing = false
                    opened = null
                    scope.launch { refreshInbox() }
                },
            )
        }
        }
        return
    }

    if (creating) {
        CreateGroupScreen(
            repository = repository,
            onClose = { creating = false },
            onCreated = { groupId ->
                creating = false
                opened = placeholderConversation(ChatKind.Group, groupId)
                scope.launch { refreshInbox() }
            },
        )
        return
    }

    val conversations = inbox?.conversations.orEmpty()
    val visible = conversations.filter { item ->
        if (filter != null && item.kind != filter) return@filter false
        chatSearchMatch("${item.title} ${item.lastBodyText}", search)
    }
    LvtScreen(
        title = "Trao đổi",
        helpAnchor = GuideAnchors.CHAT,
        refreshing = refreshing,
        onRefresh = {
            refreshing = true
            scope.launch { refreshInbox() }
        },
        showAccountHeader = true,
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Cuộc trò chuyện", style = MaterialTheme.typography.titleMedium)
                TextButton(onClick = { creating = true }) { Text("Tạo nhóm") }
            }
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text("Tìm cuộc trò chuyện…") },
                label = { Text("Tìm cuộc trò chuyện") },
            )
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FILTERS.forEach { (kind, label) ->
                    FilterChip(
                        selected = filter == kind,
                        onClick = { filter = kind },
                        label = { Text(label) },
                    )
                }
            }
            if (inbox?.backfillPending == true) {
                Text(
                    "Đang đồng bộ cuộc trò chuyện cũ…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when {
                loading && inbox == null -> Text("Đang tải…")
                listError != null && inbox == null -> Text(listError.orEmpty(), color = MaterialTheme.colorScheme.error)
                visible.isEmpty() -> Text(
                    if (conversations.isEmpty()) {
                        "Chưa có cuộc trò chuyện. Hãy tạo nhóm hoặc nhắn trong Công tác, Công việc."
                    } else {
                        "Không có cuộc trò chuyện phù hợp."
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp),
                )
                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(visible, key = { it.threadKey }) { item ->
                        ConversationRow(item, inbox?.currentUserId.orEmpty()) {
                            opened = item
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChatThreadHost(
    repository: ChatRepository,
    conversation: ChatConversation,
    onBack: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenDuty: (String) -> Unit,
    onManage: () -> Unit,
    onArchive: () -> Unit,
) {
    var groupState by remember(conversation.entityId) { mutableStateOf<ChatGroupState?>(null) }
    LaunchedEffect(conversation.kind, conversation.entityId) {
        if (conversation.kind != ChatKind.Group) return@LaunchedEffect
        while (true) {
            groupState = runCatching { repository.groupState(conversation.entityId) }.getOrNull()
            delay(POLL_MS)
        }
    }
    val canSend = conversation.kind != ChatKind.Group || groupState?.canSend != false
    val actionLabel = when (conversation.kind) {
        ChatKind.Work -> "Mở công việc"
        ChatKind.Duty -> "Mở công tác"
        ChatKind.Group -> {
            val count = groupState?.memberCount ?: conversation.memberCount
            if (count > 0) "$count thành viên" else "Thành viên"
        }
    }
    val title = conversation.title.ifBlank {
        groupState?.name?.takeIf { it.isNotBlank() } ?: chatKindLabel(conversation.kind)
    }
    ChatScreen(
        repository = repository,
        target = ChatTarget(conversation.kind, conversation.entityId, title),
        onBack = onBack,
        canSend = canSend,
        actionLabel = actionLabel,
        onAction = {
            when (conversation.kind) {
                ChatKind.Work -> onOpenWork(conversation.entityId)
                ChatKind.Duty -> onOpenDuty(conversation.entityId)
                ChatKind.Group -> onManage()
            }
        },
        markReadKey = chatThreadKey(conversation.kind, conversation.entityId),
        onArchive = onArchive,
    )
}

@Composable
private fun ConversationRow(
    item: ChatConversation,
    currentUserId: String,
    onClick: () -> Unit,
) {
    val preview = chatListPreview(item.lastBodyText, item.lastAuthorUserId, currentUserId)
    val heading = item.title.ifBlank { if (item.kind == ChatKind.Group) "Nhóm" else "Trao đổi" }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        KindMark(item.kind, heading)
        Column(modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(heading, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                preview,
                style = MaterialTheme.typography.bodySmall,
                fontStyle = if (preview == CHAT_RECALLED_PLACEHOLDER) FontStyle.Italic else FontStyle.Normal,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(chatKindLabel(item.kind), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(formatChatListTime(item.lastMessageAt), style = MaterialTheme.typography.labelSmall)
            if (item.unreadCount > 0) {
                Box(
                    modifier = Modifier
                        .padding(top = 6.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.error)
                        .padding(horizontal = 7.dp, vertical = 2.dp),
                ) {
                    Text(
                        if (item.unreadCount > 99) "99+" else item.unreadCount.toString(),
                        color = MaterialTheme.colorScheme.onError,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun KindMark(kind: ChatKind, title: String) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        when (kind) {
            ChatKind.Duty -> Icon(Icons.Outlined.CalendarMonth, contentDescription = "Công tác")
            ChatKind.Work -> Icon(Icons.Outlined.WorkOutline, contentDescription = "Công việc")
            ChatKind.Group -> Text(groupInitials(title), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun CreateGroupScreen(
    repository: ChatRepository,
    onClose: () -> Unit,
    onCreated: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var people by remember { mutableStateOf<List<ChatPerson>?>(null) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var query by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        people = runCatching { repository.directory() }.getOrElse {
            error = it.hubMessage()
            emptyList()
        }
    }
    val options = people.orEmpty().filter { person ->
        chatSearchMatch("${person.name} ${person.email} ${person.departmentName}", query)
    }
    val canSubmit = name.trim().isNotEmpty() && selected.isNotEmpty() && !saving
    LvtScreen(
        title = "Tạo nhóm",
        navigationIcon = {
            IconButton(onClick = onClose, enabled = !saving) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Đóng")
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it.take(80) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Tên nhóm") },
                placeholder = { Text("Ví dụ: Tổ chuyên môn") },
            )
            Text("Thành viên", modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text("Tìm theo tên, email, phòng ban…") },
                label = { Text("Tìm nhân sự") },
            )
            Box(modifier = Modifier.weight(1f).padding(top = 8.dp)) {
                when {
                    people == null -> Text("Đang tải danh sách…")
                    options.isEmpty() -> Text("Không có nhân sự phù hợp.")
                    else -> LazyColumn {
                        items(options, key = { it.userId }) { person ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selected = if (person.userId in selected) selected - person.userId else selected + person.userId
                                    }
                                    .padding(vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(checked = person.userId in selected, onCheckedChange = { checked ->
                                    selected = if (checked) selected + person.userId else selected - person.userId
                                })
                                Column {
                                    Text(person.name, fontWeight = FontWeight.SemiBold)
                                    val detail = listOf(person.departmentName, person.email).filter { it.isNotBlank() }.joinToString(" · ")
                                    if (detail.isNotBlank()) {
                                        Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 6.dp)) }
            Row(modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onClose, enabled = !saving, modifier = Modifier.weight(1f)) { Text("Hủy") }
                Button(
                    onClick = {
                        saving = true
                        error = null
                        scope.launch {
                            runCatching { repository.createGroup(name, selected.toList()) }
                                .onSuccess { groupId ->
                                    if (groupId.isBlank()) error = "Không thực hiện được. Vui lòng thử lại."
                                    else onCreated(groupId)
                                }
                                .onFailure { failure -> error = failure.hubMessage() }
                            saving = false
                        }
                    },
                    enabled = canSubmit,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                        disabledContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.38f),
                        disabledContentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) {
                    Text(if (saving) "Đang tạo…" else "Tạo nhóm")
                }
            }
        }
    }
}

@Composable
private fun ManageGroupScreen(
    repository: ChatRepository,
    groupId: String,
    onClose: () -> Unit,
    onLeft: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<ChatGroupState?>(null) }
    var missing by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var people by remember { mutableStateOf<List<ChatPerson>?>(null) }
    var adding by remember { mutableStateOf(setOf<String>()) }
    var query by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var generation by remember { mutableIntStateOf(0) }

    LaunchedEffect(groupId, generation) {
        val loaded = runCatching { repository.groupState(groupId) }.getOrElse {
            error = it.hubMessage()
            null
        }
        if (loaded == null) {
            missing = state == null
        } else {
            missing = false
            if (state?.groupId != loaded.groupId || name.isBlank() || pending == "rename") name = loaded.name
            state = loaded
            if (loaded.canManage && people == null) {
                people = runCatching { repository.directory() }.getOrDefault(emptyList())
            }
        }
    }

    val busy = pending.isNotEmpty()
    val memberIds = state?.members?.map { it.userId }?.toSet().orEmpty()
    val candidates = people.orEmpty().filter { it.userId !in memberIds && chatSearchMatch("${it.name} ${it.email} ${it.departmentName}", query) }

    fun run(key: String, leaveAfter: Boolean = false, action: suspend () -> Unit) {
        pending = key
        error = null
        scope.launch {
            runCatching { action() }
                .onSuccess {
                    if (leaveAfter) onLeft() else generation += 1
                }
                .onFailure { failure -> error = failure.hubMessage() }
            pending = ""
        }
    }

    LvtScreen(
        title = "Thành viên nhóm",
        navigationIcon = {
            IconButton(onClick = onClose, enabled = !busy) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Đóng")
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            when {
                state == null && !missing -> Text("Đang tải…")
                missing -> Text("Nhóm không còn tồn tại hoặc bạn không còn trong nhóm.")
                state != null -> {
                    val current = state!!
                    if (current.canManage) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it.take(80) },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            label = { Text("Tên nhóm") },
                        )
                        OutlinedButton(
                            onClick = { run("rename") { repository.renameGroup(groupId, name) } },
                            enabled = !busy && name.trim() != current.name,
                            modifier = Modifier.padding(top = 8.dp),
                        ) { Text("Đổi tên") }
                    } else {
                        Text(current.name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
                    }
                    LazyColumn(modifier = Modifier.weight(1f).padding(top = 8.dp)) {
                        items(current.members, key = { it.userId }) { member ->
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(member.name, fontWeight = FontWeight.SemiBold)
                                    val role = if (member.role == "owner") "Chủ nhóm" else "Thành viên"
                                    Text(
                                        role + if (member.isSelf) " · Bạn" else "",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (current.canManage && member.role != "owner") {
                                    TextButton(
                                        onClick = { run("remove-${member.userId}") { repository.removeMember(groupId, member.userId) } },
                                        enabled = !busy,
                                    ) { Text("Xóa") }
                                }
                            }
                        }
                        if (current.canManage) {
                            item {
                                Text("Thêm thành viên", modifier = Modifier.padding(top = 8.dp))
                                OutlinedTextField(
                                    value = query,
                                    onValueChange = { query = it },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = true,
                                    placeholder = { Text("Tìm theo tên, email, phòng ban…") },
                                    label = { Text("Tìm nhân sự") },
                                )
                            }
                            items(candidates, key = { "add-${it.userId}" }) { person ->
                                Row(
                                    modifier = Modifier.fillMaxWidth().clickable {
                                        adding = if (person.userId in adding) adding - person.userId else adding + person.userId
                                    },
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Checkbox(checked = person.userId in adding, onCheckedChange = { checked ->
                                        adding = if (checked) adding + person.userId else adding - person.userId
                                    })
                                    Text(person.name)
                                }
                            }
                            item {
                                OutlinedButton(
                                    onClick = {
                                        val ids = adding.toList()
                                        run("add") {
                                            repository.addMembers(groupId, ids)
                                            adding = emptySet()
                                        }
                                    },
                                    enabled = !busy && adding.isNotEmpty(),
                                ) { Text("Thêm vào nhóm") }
                            }
                        }
                    }
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 6.dp)) }
            Row(modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (state?.canLeave == true) {
                    OutlinedButton(onClick = { confirm = "leave" }, enabled = !busy, modifier = Modifier.weight(1f)) {
                        Text("Rời nhóm")
                    }
                }
                if (state?.canDissolve == true) {
                    Button(
                        onClick = { confirm = "dissolve" },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                            contentColor = MaterialTheme.colorScheme.onError,
                        ),
                    ) { Text("Giải tán nhóm") }
                }
            }
        }
    }
    if (confirm.isNotEmpty()) {
        val dissolve = confirm == "dissolve"
        AlertDialog(
            onDismissRequest = { if (!busy) confirm = "" },
            title = { Text(if (dissolve) "Giải tán nhóm này?" else "Rời khỏi nhóm này?") },
            confirmButton = {
                Button(
                    onClick = {
                        val action = confirm
                        confirm = ""
                        run(action, leaveAfter = true) {
                            if (action == "dissolve") repository.dissolveGroup(groupId) else repository.leaveGroup(groupId)
                        }
                    },
                    enabled = !busy,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) { Text(if (dissolve) "Giải tán" else "Rời nhóm") }
            },
            dismissButton = {
                TextButton(onClick = { confirm = "" }, enabled = !busy) { Text("Hủy") }
            },
        )
    }
}

private fun placeholderConversation(kind: ChatKind, entityId: String) = ChatConversation(
    threadKey = chatThreadKey(kind, entityId),
    kind = kind,
    entityId = entityId,
    title = "",
    lastBodyText = "",
    lastMessageAt = 0L,
    lastAuthorUserId = "",
    unreadCount = 0,
)

private fun groupInitials(title: String): String {
    val parts = title.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (parts.isEmpty()) return "N"
    return parts.take(2).joinToString("") { it.take(1).uppercase() }
}

private fun Throwable.hubMessage(): String {
    val raw = when (this) {
        is ConvexException -> "$code $message"
        else -> message.orEmpty()
    }
    return chatHubFailureMessage(raw)
}
