package lvt.crm.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material.icons.outlined.WorkOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import lvt.crm.R
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.duties.DutyListTab
import lvt.crm.ui.work.WorkDashboardFilter
import lvt.crm.ui.components.GuideAnchors

@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel,
    tabOpenToken: Int,
    onOpenDuties: (DutyListTab) -> Unit,
    onOpenWork: (WorkDashboardFilter?) -> Unit,
) {
    val state by viewModel.uiState.collectAsState()
    LaunchedEffect(tabOpenToken) { viewModel.refresh() }

    LvtScreen(
        title = stringResource(R.string.nav_overview),
        helpAnchor = GuideAnchors.OVERVIEW,
        refreshing = state.refreshing || state.loading,
        onRefresh = { viewModel.refresh() },
        showAccountHeader = true,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            Text(
                "Theo dõi những nội dung cần bạn xử lý.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 16.dp),
            )
            OverviewCard(
                title = "Công tác",
                subtitle = "Lịch điều phối",
                icon = Icons.Outlined.WorkOutline,
                primaryTitle = "Sắp diễn ra",
                primaryValue = state.upcomingDuties,
                secondaryTitle = "Đang diễn ra",
                secondaryValue = state.ongoingDuties,
                loading = state.loading,
                error = state.error,
                onClick = { onOpenDuties(DutyListTab.Upcoming) },
                onPrimaryClick = { onOpenDuties(DutyListTab.Upcoming) },
                onSecondaryClick = { onOpenDuties(DutyListTab.Ongoing) },
            )
            Spacer(modifier = Modifier.height(12.dp))
            OverviewCard(
                title = "Công việc",
                subtitle = "Tiến độ vận hành",
                icon = Icons.Outlined.TaskAlt,
                primaryTitle = "Chờ duyệt nộp",
                primaryValue = state.pendingApproval,
                secondaryTitle = "Cần thực hiện",
                secondaryValue = state.pendingExecution,
                loading = state.loading,
                error = state.error,
                onClick = { onOpenWork(null) },
                onPrimaryClick = { onOpenWork(WorkDashboardFilter.PendingApproval) },
                onSecondaryClick = { onOpenWork(WorkDashboardFilter.NeedsExecution) },
            )
            Spacer(modifier = Modifier.height(16.dp))
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = { Text("Đồng bộ dữ liệu") },
                    supportingContent = {
                        Text(
                            when {
                                state.loading || state.refreshing -> "Đang lấy dữ liệu mới nhất…"
                                state.error -> "Chưa thể đồng bộ. Kéo xuống hoặc chạm Làm mới để thử lại."
                                else -> "Dữ liệu đang hiển thị đã được cập nhật."
                            },
                        )
                    },
                    leadingContent = {
                        if (state.loading || state.refreshing) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(
                                Icons.Outlined.CheckCircle,
                                contentDescription = null,
                                tint = if (state.error) {
                                    MaterialTheme.colorScheme.error
                                } else {
                                    MaterialTheme.colorScheme.primary
                                },
                            )
                        }
                    },
                    trailingContent = if (state.error) {
                        {
                            FilledTonalButton(onClick = { viewModel.refresh() }) {
                                Text("Làm mới")
                            }
                        }
                    } else {
                        null
                    },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun OverviewCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    primaryTitle: String,
    primaryValue: Int,
    secondaryTitle: String,
    secondaryValue: Int,
    loading: Boolean,
    error: Boolean,
    onClick: () -> Unit,
    onPrimaryClick: () -> Unit,
    onSecondaryClick: () -> Unit,
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            ListItem(
                headlineContent = { Text(title) },
                supportingContent = { Text(subtitle) },
                leadingContent = {
                    Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                },
                modifier = Modifier.clickable(onClick = onClick),
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Metric(
                    title = if (error) "Chưa tải được" else primaryTitle,
                    value = if (loading) null else if (error) "!" else primaryValue.toString(),
                    modifier = Modifier
                        .weight(1f)
                        .clickable(onClick = onPrimaryClick),
                )
                Metric(
                    title = if (error) "Chạm để mở" else secondaryTitle,
                    value = if (loading) null else if (error) "!" else secondaryValue.toString(),
                    modifier = Modifier
                        .weight(1f)
                        .clickable(onClick = onSecondaryClick),
                )
            }
        }
    }
}

@Composable
private fun Metric(
    title: String,
    value: String?,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        if (value == null) {
            CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 2.dp)
        } else {
            Text(value, style = MaterialTheme.typography.headlineMedium)
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            title,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
