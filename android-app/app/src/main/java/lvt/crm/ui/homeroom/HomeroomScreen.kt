package lvt.crm.ui.homeroom

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import lvt.crm.data.homeroom.HomeroomClassSummary
import lvt.crm.data.homeroom.HomeroomOverview
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.components.GuideAnchors

/**
 * Lớp học › Lớp chủ nhiệm. [onOpenAttendance] (admin/mod, or a GVCN who is also Giám thị) opens the
 * Điểm danh screen; Giám thị alone gets Điểm danh as its own tab instead.
 */
@Composable
fun HomeroomScreen(
    viewModel: HomeroomViewModel,
    canManage: Boolean = false,
    onOpenAttendance: (() -> Unit)? = null,
    classLogsLoader: lvt.crm.ui.teaching.ClassLogsLoader? = null,
) {
    val state by viewModel.uiState.collectAsState()
    var management by remember(viewModel) { mutableStateOf<lvt.crm.data.homeroom.HomeroomManagementStore?>(null) }
    if (management != null) {
        HomeroomManagementScreen(management!!) { management = null; viewModel.refresh() }
        return
    }
    val currentDetail by viewModel.detailState.collectAsState()
    if (currentDetail != null) {
        val selectedDetail = currentDetail!!
        androidx.compose.runtime.DisposableEffect(selectedDetail) {
            if (!selectedDetail.uiState.value.loading) selectedDetail.refresh()
            onDispose { selectedDetail.close() }
        }
        HomeroomDetailScreen(selectedDetail, viewModel::closeDetail, classLogsLoader)
        return
    }
    LvtScreen(
        title = "Lớp học",
        helpAnchor = GuideAnchors.HOMEROOM,
        refreshing = state.refreshing,
        onRefresh = viewModel::refresh,
        showAccountHeader = true,
    ) {
        Column(Modifier.fillMaxSize()) {
            if (state.years.isNotEmpty() || onOpenAttendance != null) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val actionsEnabled = !state.loading && !state.refreshing && state.selectedYearId != null
                    ContextControls(
                        years = state.years.map { it.id to it.name },
                        selectedYearId = state.selectedYearId,
                        onYear = viewModel::selectYear,
                        actions = buildList {
                            if (onOpenAttendance != null) add(Triple("Điểm danh", true, onOpenAttendance))
                            if (canManage) add(Triple("Danh mục", actionsEnabled, { management = viewModel.management() }))
                        },
                    )
                    if (state.years.isNotEmpty()) DayNavigator(date = state.date, onDate = viewModel::selectDate)
                }
            }
            Box(Modifier.weight(1f)) {
                when {
                    state.loading -> CenteredLoading()
                    state.error != null -> StatePanel(
                        icon = Icons.Outlined.WarningAmber,
                        title = "Chưa tải được dữ liệu",
                        message = "${state.error.orEmpty()}\nNgày Việt Nam: ${formatDate(state.date)}",
                        action = { Button(onClick = viewModel::refresh) { Text("Thử lại") } },
                    )
                    state.years.isEmpty() -> StatePanel(
                        icon = Icons.Outlined.CalendarMonth,
                        title = "Chưa có năm học",
                        message = "Quản trị viên cần tạo năm học trước khi xem điểm danh.",
                    )
                    else -> LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        overviewItems(state.overview) { klass ->
                            viewModel.openClass(klass.id)
                        }
                    }
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.overviewItems(overview: HomeroomOverview?, onClass: (HomeroomClassSummary) -> Unit) {
    if (overview == null) return
    val schoolDay = overview.schoolDay.isSchoolDay && !overview.schoolDay.outsideYear
    item {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when {
                overview.schoolDay.outsideYear -> HomeroomBanner("Ngoài năm học", "Ngày đã chọn nằm ngoài năm học ${overview.schoolYear.name}.", HomeroomTone.Info, Icons.Outlined.EventBusy)
                !overview.schoolDay.isSchoolDay -> HomeroomBanner(
                    if (overview.date == overview.today) "Hôm nay không phải ngày học" else "Không phải ngày học",
                    overview.schoolDay.note.ifBlank { "Không cần điểm danh." },
                    HomeroomTone.Info,
                    Icons.Outlined.EventBusy,
                )
                else -> {
                    StatTiles(HomeroomPresentation.overviewStats(overview.counts))
                    Text(
                        HomeroomPresentation.overviewSummary(overview.studentCount, overview.classes.size, overview.attendanceRate, overview.ratedRows),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            if (schoolDay && overview.missingUpload.shouldAlert) {
                HomeroomBanner(
                    "Đã quá ${overview.missingUpload.cutoffTime} nhưng ${overview.missingUpload.missingClassCodes.size} lớp chưa được Giám thị điểm danh.",
                    overview.missingUpload.missingClassCodes.take(12).joinToString() + if (overview.missingUpload.missingClassCodes.size > 12) "…" else "",
                    HomeroomTone.Warning,
                    Icons.Outlined.WarningAmber,
                )
            }
        }
    }
    if (overview.classes.isEmpty()) {
        item { HomeroomBanner("Chưa có lớp", "Bạn chưa được phân công lớp chủ nhiệm trong ngày này.", HomeroomTone.Neutral, Icons.Outlined.Groups) }
    } else {
        itemsIndexed(overview.classes, key = { _, row -> row.id }) { index, row ->
            ListSegment(index, overview.classes.size) {
                HomeroomListRow(
                    title = HomeroomPresentation.classTitle(row),
                    subtitle = HomeroomPresentation.classSubtitle(row),
                    chips = HomeroomPresentation.classChips(row, schoolDay),
                    onClick = { onClass(row) },
                )
            }
        }
    }
}

@Composable
private fun ContextControls(
    years: List<Pair<String, String>>,
    selectedYearId: String?,
    onYear: (String) -> Unit,
    actions: List<Triple<String, Boolean, () -> Unit>>,
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = years.firstOrNull { it.first == selectedYearId }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (years.isNotEmpty()) Box {
            TextButton(onClick = { expanded = true }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text("Năm học ${selected?.second ?: "—"}", fontWeight = FontWeight.SemiBold)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                years.forEach { (id, name) ->
                    DropdownMenuItem(text = { Text(name) }, onClick = { expanded = false; onYear(id) })
                }
            }
        }
        Box(Modifier.weight(1f))
        actions.forEach { (label, enabled, action) ->
            OutlinedButton(enabled = enabled, onClick = action, modifier = Modifier.heightIn(min = 48.dp)) { Text(label, maxLines = 1) }
        }
    }
}

@Composable
private fun CenteredLoading() = Column(
    modifier = Modifier.fillMaxSize(),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    CircularProgressIndicator()
    Text("Đang tải lớp chủ nhiệm…", modifier = Modifier.padding(top = 12.dp))
}

internal fun formatDate(value: String): String = runCatching {
    val date = LocalDate.parse(value)
    "%02d/%02d/%04d".format(date.dayOfMonth, date.monthValue, date.year)
}.getOrDefault(value)
