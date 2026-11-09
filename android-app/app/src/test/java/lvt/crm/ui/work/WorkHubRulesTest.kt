package lvt.crm.ui.work

import org.junit.Assert.assertEquals
import org.junit.Test

class WorkHubRulesTest {
    @Test fun `without the work menu only Viec cua toi is shown`() {
        assertEquals(WorkHubTab.Todos, WorkHubRules.visibleTab(WorkHubTab.Work, canSeeWork = false))
        assertEquals(WorkHubTab.Work, WorkHubRules.visibleTab(WorkHubTab.Work, canSeeWork = true))
        assertEquals(WorkHubTab.Todos, WorkHubRules.visibleTab(WorkHubTab.Todos, canSeeWork = true))
    }

    @Test fun `todo reminders open Viec cua toi and other work focus opens Cong viec`() {
        assertEquals(WorkHubTab.Todos, WorkHubRules.tabForFocus(isTodoFocus = true, canSeeWork = true))
        assertEquals(WorkHubTab.Work, WorkHubRules.tabForFocus(isTodoFocus = false, canSeeWork = true))
        assertEquals(WorkHubTab.Todos, WorkHubRules.tabForFocus(isTodoFocus = false, canSeeWork = false))
    }
}
