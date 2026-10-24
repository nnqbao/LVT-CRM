package lvt.crm.ui.duties

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.duties.DutiesRepository
import lvt.crm.data.duties.DutyWeekState
import lvt.crm.data.duties.SharedDutyEvent
import lvt.crm.data.duties.SharedDutyWeek
import lvt.crm.data.duties.SharedSchedulePdf
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.homeroom.HomeroomBanner
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.toneColors
import lvt.crm.ui.components.GuideAnchors

private const val RETURN_NOTE_MAX = 500

private enum class WeekConfirm { Submit, Approve, Return }

/**
 * Lịch công tác chung as a day-by-day list. Văn thư (admin/mod) submits and edits,
 * BGH approves or returns the whole week, everybody else reads the approved copy.
 */
@Composable
fun SharedWeekScreen(
    dutiesRepository: DutiesRepository,
    initialWeekStart: String?,
    openToken: String?,
    onBack: () -> Unit,
) {
    var weekStart by remember { mutableStateOf(SharedWeekPresentation.weekStart(initialWeekStart ?: todayIsoDate())) }
    LaunchedEffect(openToken, initialWeekStart) {
        if (!initialWeekStart.isNullOrBlank()) weekStart = SharedWeekPresentation.weekStart(initialWeekStart)
    }
    var data by remember { mutableStateOf<SharedDutyWeek?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<WeekConfirm?>(null) }
    var editing by remember { mutableStateOf<SharedDutyEvent?>(null) }
    var preview by remember { mutableStateOf<SharedSchedulePdf?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(weekStart, reload) {
        loading = true
        error = null
        runCatching { dutiesRepository.sharedWeek(weekStart, SharedWeekPresentation.weekEnd(weekStart)) }
            .onSuccess { data = it }
            .onFailure { error = (it as? ConvexException)?.message ?: "Không tải được lịch công tác chung. Hãy thử lại." }
        loading = false
    }

    preview?.let { pdf ->
        SharedDutySchedulePreviewScreen(pdf = pdf, onBack = { preview = null })
        return
    }
    editing?.let { event ->
        DutyEditScreen(
            dutiesRepository = dutiesRepository,
            event = event,
            onClose = { editing = null },
            onSaved = {
                editing = null
                feedback = "Đã lưu. Thay đổi chờ Ban Giám hiệu duyệt."
                reload += 1
            },
        )
        return
    }

    fun act(success: String, action: suspend () -> Unit) {
        if (busy) return
        busy = true
        feedback = null
        scope.launch {
            runCatching { action() }
                .onSuccess { feedback = success }
                .onFailure { feedback = (it as? ConvexException)?.message ?: "Không thực hiện được. Hãy thử lại." }
            busy = false
            confirm = null
            reload += 1
        }
    }

    BackHandler(onBack = onBack)
    val current = data
    val week = current?.week
    val canSend = SharedWeekPresentation.canSubmit(week, current?.canSubmit == true)
    val canDecide = SharedWeekPresentation.canDecide(week, current?.canReview == true)
    LvtScreen(
        title = "Lịch công tác chung",
        helpAnchor = GuideAnchors.DUTIES,
        refreshing = loading,
        onRefresh = { reload += 1 },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại") }
        },
        actions = {
            IconButton(onClick = {
                if (busy) return@IconButton
                busy = true
                scope.launch {
                    runCatching { dutiesRepository.downloadSharedSchedulePdf("week", weekStart) }
                        .onSuccess { preview = it }
                        .onFailure { feedback = (it as? ConvexException)?.message ?: "Không tải được PDF. Hãy thử lại." }
                    busy = false
                }
            }) { Icon(Icons.Outlined.PictureAsPdf, contentDescription = "Xem PDF") }
        },
    ) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { weekStart = SharedWeekPresentation.shiftWeek(weekStart, -1) }) {
                    Icon(Icons.Outlined.ChevronLeft, contentDescription = "Tuần trước")
                }
                TextButton(
                    onClick = { weekStart = SharedWeekPresentation.weekStart(todayIsoDate()) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text(SharedWeekPresentation.weekLabel(weekStart), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                }
                IconButton(onClick = { weekStart = SharedWeekPresentation.shiftWeek(weekStart, 1) }) {
                    Icon(Icons.Outlined.ChevronRight, contentDescription = "Tuần sau")
                }
            }
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                error?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error) } }
                feedback?.let { message ->
                    item { Text(message, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium) }
                }
                if (current == null) {
                    if (loading) item { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) { CircularProgressIndicator() } }
                    return@LazyColumn
                }
                if (week != null && current.viewer != "public" && !(week.status == "empty" && !current.canSubmit)) {
                    item { WeekStatusCard(week, manager = current.canSubmit) }
                }
                if (SharedWeekPresentation.showUnapprovedNotice(current.viewer, current.events.size)) {
                    item {
                        HomeroomBanner(
                            title = "Lịch tuần này chưa được duyệt",
                            message = "Nhà trường sẽ công bố lịch công tác sau khi Ban Giám hiệu duyệt.",
                            tone = HomeroomTone.Neutral,
                            icon = Icons.Outlined.EventBusy,
                        )
                    }
                    return@LazyColumn
                }
                SharedWeekPresentation.days(weekStart, current.events).forEach { day ->
                    item(key = "day-${day.iso}") {
                        Text(
                            day.title,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp, start = 4.dp),
                        )
                    }
                    if (day.events.isEmpty()) {
                        item(key = "empty-${day.iso}") {
                            Text(
                                "Không có công tác",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.outline,
                                modifier = Modifier.padding(start = 4.dp),
                            )
                        }
                    }
                    items(day.events, key = { "${day.iso}-${it.id}" }) { event ->
                        val editable = current.canSubmit && event.canManage
                        SharedEventRow(event, editable = editable, onClick = { editing = event })
                    }
                }
            }
            if (canSend || canDecide) {
                Surface(tonalElevation = 3.dp) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (canDecide) {
                            OutlinedButton(
                                onClick = { confirm = WeekConfirm.Return },
                                enabled = !busy,
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            ) { Text("Trả lại") }
                            Button(
                                onClick = { confirm = WeekConfirm.Approve },
                                enabled = !busy,
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                            ) { Text("Duyệt lịch tuần") }
                        } else if (week != null) {
                            Button(
                                onClick = { confirm = WeekConfirm.Submit },
                                enabled = !busy,
                                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            ) { Text(SharedWeekPresentation.submitLabel(week)) }
                        }
                    }
                }
            }
        }
    }

    val label = SharedWeekPresentation.weekLabel(weekStart).removePrefix("Tuần ")
    when (confirm) {
        WeekConfirm.Submit -> week?.let {
            ConfirmDialog(
                title = "Nộp lịch tuần $label?",
                message = if (it.missingParticipants > 0) {
                    "Còn ${it.missingParticipants} công tác chưa có thành phần. Vẫn nộp Ban Giám hiệu duyệt?"
                } else {
                    "Ban Giám hiệu sẽ nhận được thông báo."
                },
                confirmLabel = "Nộp duyệt",
                busy = busy,
                onDismiss = { confirm = null },
                onConfirm = { act("Đã nộp lịch tuần cho Ban Giám hiệu.") { dutiesRepository.submitWeek(weekStart) } },
            )
        }
        WeekConfirm.Approve -> week?.submittedAt?.let { submittedAt ->
            ConfirmDialog(
                title = "Duyệt lịch tuần $label?",
                message = "Giáo viên sẽ thấy lịch này và nhận thông báo.",
                confirmLabel = "Duyệt",
                busy = busy,
                onDismiss = { confirm = null },
                onConfirm = { act("Đã duyệt lịch tuần.") { dutiesRepository.approveWeek(weekStart, submittedAt) } },
            )
        }
        WeekConfirm.Return -> week?.submittedAt?.let { submittedAt ->
            ReturnDialog(
                label = label,
                busy = busy,
                onDismiss = { confirm = null },
                onConfirm = { note ->
                    act("Đã trả lại lịch tuần cho văn thư.") { dutiesRepository.returnWeek(weekStart, submittedAt, note) }
                },
            )
        }
        null -> Unit
    }
}

@Composable
private fun WeekStatusCard(week: DutyWeekState, manager: Boolean) {
    val colors = toneColors(SharedWeekPresentation.tone(week.status))
    val copy = if (manager) SharedWeekPresentation.managerCopy(week) else SharedWeekPresentation.reviewerCopy(week)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.background)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            SharedWeekPresentation.pill(week.status),
            color = colors.text,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            modifier = Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 10.dp, vertical = 3.dp),
        )
        Text(copy.text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        copy.hint?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (week.changes.isNotEmpty() && week.status != "approved") {
            week.changes.take(6).forEach { change ->
                Text(
                    "${SharedWeekPresentation.changeLabel(change.kind)} · ${change.title}",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                )
            }
            if (week.changes.size > 6) {
                Text("… và ${week.changes.size - 6} thay đổi khác", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun SharedEventRow(event: SharedDutyEvent, editable: Boolean, onClick: () -> Unit) {
    val pending = event.approvalChange != null
    val background = if (pending) toneColors(HomeroomTone.Warning).background else MaterialTheme.colorScheme.surfaceContainerLow
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .then(if (editable) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            SharedWeekPresentation.timeLabel(event),
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.width(56.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(event.title.ifBlank { event.content }, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
                event.approvalChange?.let { change ->
                    val tone = if (change == "added") HomeroomTone.Success else HomeroomTone.Warning
                    val chip = toneColors(tone)
                    Text(
                        if (change == "added") "Mới" else "Sửa",
                        color = chip.text,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(MaterialTheme.colorScheme.surface)
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }
            }
            val participants = SharedWeekPresentation.participants(event)
            val meta = listOf(event.locationText.trim(), participants).filter { it.isNotBlank() }.joinToString(" · ")
            if (meta.isNotBlank()) {
                Text(meta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (editable && !SharedWeekPresentation.hasParticipants(event)) {
                Text(
                    "+ Thêm thành phần",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Bold,
                    color = toneColors(HomeroomTone.Success).text,
                )
            }
        }
    }
}

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    busy: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { Button(onClick = onConfirm, enabled = !busy) { Text(if (busy) "Đang xử lý…" else confirmLabel) } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Hủy") } },
    )
}

@Composable
private fun ReturnDialog(label: String, busy: Boolean, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var note by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Trả lại lịch tuần $label") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Văn thư sẽ thấy lý do này để sửa lại.", style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it.take(RETURN_NOTE_MAX) },
                    minLines = 3,
                    placeholder = { Text("Ví dụ: Thứ Tư đổi giờ dự giờ sang 9g00.") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(note.trim()) },
                enabled = !busy && note.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
            ) { Text(if (busy) "Đang gửi…" else "Trả lại") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Hủy") } },
    )
}
