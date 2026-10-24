package lvt.crm.ui.teaching

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import lvt.crm.data.teaching.ClassLessonLog
import lvt.crm.ui.components.GuideAnchors
import lvt.crm.ui.components.IconTabBar
import lvt.crm.ui.components.IconTabItem
import lvt.crm.ui.components.LocalScreenTabs
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.homeroom.HomeroomScreen
import lvt.crm.ui.homeroom.HomeroomViewModel

/** The five sections of Lớp học (docs/native-teaching-auth-contract.md §1). */
enum class ClassesSection(val label: String, val icon: ImageVector) {
    Overview("Tổng quan", Icons.Outlined.Home),
    Homeroom("Chủ nhiệm", Icons.Outlined.Groups),
    Teaching("Giảng dạy", Icons.Outlined.EditNote),
    Schedule("Lịch dạy", Icons.Outlined.CalendarMonth),
    Gradebook("Học bạ", Icons.Outlined.School),
}

/** Loads Sổ đầu bài of a class (`lessonLogs:listForClass`) for the class detail tab. */
typealias ClassLogsLoader = suspend (classId: String, from: String, to: String) -> List<ClassLessonLog>

/**
 * Lớp học menu (formerly Lớp chủ nhiệm). "Lớp chủ nhiệm" keeps the existing homeroom screens; the
 * other sections are new. Settings (giáo viên, lịch dạy, môn học, loại kiểm tra) stay web-only.
 */
@Composable
fun ClassesHubScreen(
    homeroomViewModel: HomeroomViewModel,
    teachingViewModel: TeachingViewModel,
    gradebookViewModel: GradebookViewModel,
    canManage: Boolean,
    onOpenAttendance: (() -> Unit)?,
    classLogsLoader: ClassLogsLoader?,
) {
    var section by rememberSaveable { mutableStateOf(ClassesSection.Overview) }
    val state by teachingViewModel.uiState.collectAsState()
    val gradebookState by gradebookViewModel.uiState.collectAsState()

    LaunchedEffect(section, state.selectedYearId) {
        when (section) {
            ClassesSection.Schedule -> teachingViewModel.ensureSchedule()
            ClassesSection.Gradebook -> gradebookViewModel.setYear(state.selectedYearId)
            else -> Unit
        }
    }

    val tabs: @Composable () -> Unit = {
        IconTabBar(
            items = ClassesSection.entries.map { IconTabItem(it.label, it.icon) },
            selectedIndex = section.ordinal,
            onSelect = { index ->
                section = ClassesSection.entries[index]
                teachingViewModel.clearMessage()
            },
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }

    CompositionLocalProvider(LocalScreenTabs provides tabs) {
        if (section == ClassesSection.Homeroom) {
            HomeroomScreen(
                homeroomViewModel,
                canManage = canManage,
                onOpenAttendance = onOpenAttendance,
                classLogsLoader = classLogsLoader,
            )
            return@CompositionLocalProvider
        }
        val refreshing = state.refreshing || (section == ClassesSection.Gradebook && (gradebookState.classesLoading || gradebookState.studentsLoading || gradebookState.recordLoading))
        LvtScreen(
            title = "Lớp học",
            helpAnchor = GuideAnchors.HOMEROOM,
            refreshing = refreshing,
            onRefresh = {
                if (section == ClassesSection.Gradebook) gradebookViewModel.refresh() else teachingViewModel.refresh()
            },
            showAccountHeader = true,
        ) {
            Column(Modifier.fillMaxSize()) {
                val atRoot = section != ClassesSection.Gradebook || (gradebookState.openClassId == null && gradebookState.openStudentId == null)
                if (state.years.size > 1 && atRoot) {
                    YearSelector(
                        years = state.years,
                        selectedYearId = state.selectedYearId,
                        onYear = teachingViewModel::selectYear,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                }
                Box(Modifier.weight(1f)) {
                    when {
                        state.loading && state.teaching == null -> Column(
                            Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                        ) {
                            CircularProgressIndicator()
                            Text("Đang tải Lớp học…", modifier = Modifier.padding(top = 12.dp))
                        }
                        state.error != null && state.teaching == null -> StatePanel(
                            icon = Icons.Outlined.WarningAmber,
                            title = "Chưa tải được dữ liệu",
                            message = state.error.orEmpty(),
                            action = { Button(onClick = teachingViewModel::refresh) { Text("Thử lại") } },
                        )
                        state.selectedYearId == null -> StatePanel(
                            icon = Icons.Outlined.CalendarMonth,
                            title = "Chưa có năm học",
                            message = "Quản trị viên cần tạo năm học trước.",
                        )
                        else -> when (section) {
                            ClassesSection.Overview -> TeachingOverviewContent(
                                state = state,
                                onOpenTeaching = { section = ClassesSection.Teaching },
                                onOpenHomeroom = { section = ClassesSection.Homeroom },
                                onOpenHomeroomClass = { classId ->
                                    val yearId = state.selectedYearId ?: return@TeachingOverviewContent
                                    section = ClassesSection.Homeroom
                                    homeroomViewModel.focusClass(yearId, state.now.date, classId)
                                },
                            )
                            ClassesSection.Teaching -> TeachingClassesContent(state, onOpen = teachingViewModel::openLessonLog)
                            ClassesSection.Schedule -> ScheduleContent(
                                schedule = state.schedule,
                                loading = state.scheduleLoading,
                                error = state.scheduleError,
                                catalog = state.catalog,
                                today = state.now.date,
                                onRetry = teachingViewModel::retrySchedule,
                            )
                            ClassesSection.Gradebook -> GradebookContent(gradebookViewModel, gradebookState)
                            ClassesSection.Homeroom -> Unit
                        }
                    }
                }
            }
        }
        LessonLogSheet(state, teachingViewModel)
    }
}
