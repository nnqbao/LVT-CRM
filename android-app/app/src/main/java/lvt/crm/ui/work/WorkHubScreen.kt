package lvt.crm.ui.work

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import lvt.crm.ui.components.LocalScreenTabs
import lvt.crm.ui.todos.PersonalTodosScreen
import lvt.crm.ui.todos.PersonalTodosViewModel

enum class WorkHubTab { Work, Todos }

/** Which hub tab to show. Without the work menu only "Việc của tôi" exists. Mirrors web WorkHub.jsx. */
object WorkHubRules {
    fun visibleTab(selected: WorkHubTab, canSeeWork: Boolean): WorkHubTab = if (canSeeWork) selected else WorkHubTab.Todos

    /** Tab a notification focus switches to: todo reminders → Việc của tôi, other work items → Công việc. */
    fun tabForFocus(isTodoFocus: Boolean, canSeeWork: Boolean): WorkHubTab =
        if (isTodoFocus || !canSeeWork) WorkHubTab.Todos else WorkHubTab.Work
}

/**
 * Công việc menu: "Công việc" (work documents, only when the work menu is visible) and "Việc của tôi"
 * (every active account). [focusToken] changes when a notification targets this hub; [todoFocusId] is
 * set when it is a todo reminder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkHubScreen(
    canSeeWork: Boolean,
    todosViewModel: PersonalTodosViewModel,
    focusToken: String?,
    todoFocusId: String?,
    workContent: @Composable () -> Unit,
) {
    var selected by rememberSaveable { mutableStateOf(if (canSeeWork) WorkHubTab.Work else WorkHubTab.Todos) }
    var consumedFocus by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(focusToken) {
        if (focusToken == null || focusToken == consumedFocus) return@LaunchedEffect
        consumedFocus = focusToken
        selected = WorkHubRules.tabForFocus(todoFocusId != null, canSeeWork)
        if (todoFocusId != null) todosViewModel.focus(todoFocusId)
    }
    val tab = WorkHubRules.visibleTab(selected, canSeeWork)
    val tabs: (@Composable () -> Unit)? = if (!canSeeWork) null else {
        {
            PrimaryTabRow(selectedTabIndex = tab.ordinal) {
                Tab(
                    selected = tab == WorkHubTab.Work,
                    onClick = { selected = WorkHubTab.Work },
                    text = { Text("Công việc") },
                )
                Tab(
                    selected = tab == WorkHubTab.Todos,
                    onClick = { selected = WorkHubTab.Todos },
                    text = { Text("Việc của tôi") },
                )
            }
        }
    }
    CompositionLocalProvider(LocalScreenTabs provides tabs) {
        when (tab) {
            WorkHubTab.Work -> workContent()
            WorkHubTab.Todos -> PersonalTodosScreen(todosViewModel)
        }
    }
}
