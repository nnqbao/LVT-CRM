package lvt.crm.ui.homeroom

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.teaching.ClassLessonLog
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.ui.teaching.ClassLogsLoader
import lvt.crm.ui.teaching.ErrorBlock
import lvt.crm.ui.teaching.LoadingRow
import lvt.crm.ui.teaching.MutedText
import lvt.crm.ui.teaching.PeriodStepper
import lvt.crm.ui.teaching.StaticStars
import lvt.crm.ui.teaching.TeachingPresentation
import lvt.crm.ui.teaching.formatTimestamp

/** One week of Sổ đầu bài of a class (GVCN / admin view), Monday → Sunday. */
internal class ClassLessonLogsState(
    val from: String,
    val to: String,
    val rows: List<ClassLessonLog>?,
    val error: String?,
    val canNext: Boolean,
    val onPrevious: () -> Unit,
    val onNext: () -> Unit,
    val onRetry: () -> Unit,
)

@Composable
internal fun rememberClassLessonLogs(classId: String, active: Boolean, loader: ClassLogsLoader?): ClassLessonLogsState {
    val today = remember { TeachingSchedule.vietnamNow().date }
    var from by remember(classId) { mutableStateOf(TeachingSchedule.weekStart(today)) }
    var rows by remember(classId, from) { mutableStateOf<List<ClassLessonLog>?>(null) }
    var error by remember(classId, from) { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val to = TeachingSchedule.addDays(from, 6)
    LaunchedEffect(classId, from, active, reload, loader) {
        if (!active || loader == null) return@LaunchedEffect
        error = null
        rows = null
        try {
            rows = loader(classId, from, to)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = (e as? ConvexException)?.message ?: ConvexHttpClient.humanize(e.message ?: "LOAD_FAILED")
        }
    }
    return ClassLessonLogsState(
        from = from,
        to = to,
        rows = rows,
        error = error,
        canNext = to < today,
        onPrevious = { from = TeachingSchedule.addDays(from, -7) },
        onNext = { if (to < today) from = TeachingSchedule.addDays(from, 7) },
        onRetry = { reload++ },
    )
}

internal fun LazyListScope.classLessonLogItems(state: ClassLessonLogsState) {
    item(key = "logs-head") {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Sổ đầu bài", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
            val average = state.rows?.let(TeachingPresentation::weeklyAverage).orEmpty()
            MutedText(
                "Đánh giá lớp qua từng tiết học do giáo viên bộ môn ghi." +
                    if (average.isNotEmpty()) " Trung bình tuần: $average/5 sao." else "",
            )
            PeriodStepper(
                label = "${TeachingSchedule.formatDate(state.from)} – ${TeachingSchedule.formatDate(state.to)}",
                canPrevious = true,
                canNext = state.canNext,
                onPrevious = state.onPrevious,
                onNext = state.onNext,
                previousLabel = "Tuần trước",
                nextLabel = "Tuần sau",
            )
        }
    }
    val rows = state.rows
    when {
        state.error != null -> item(key = "logs-error") { ErrorBlock(state.error, state.onRetry) }
        rows == null -> item(key = "logs-loading") { LoadingRow("Đang tải Sổ đầu bài…") }
        rows.isEmpty() -> item(key = "logs-empty") {
            HomeroomBanner("Chưa có đánh giá tiết học trong tuần này.", null, HomeroomTone.Neutral, Icons.Outlined.EditNote)
        }
        else -> items(rows, key = { "log-${it.id}" }) { row -> LessonLogCard(row) }
    }
}

@Composable
private fun LessonLogCard(row: ClassLessonLog) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${TeachingSchedule.dayTitle(row.date)} · ${TeachingSchedule.periodLabel(row.session, row.period)}",
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                StaticStars(row.rating)
            }
            Text(listOf(row.subjectName, row.teacherName).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "—" })
            Text(row.comment.ifBlank { "—" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            MutedText("Ghi lúc ${formatTimestamp(row.updatedAt)}")
        }
    }
}
