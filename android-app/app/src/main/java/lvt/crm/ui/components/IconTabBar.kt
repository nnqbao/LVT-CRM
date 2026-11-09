package lvt.crm.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** One section of an [IconTabBar]. [badgeCount] ≤ 0 shows no badge. */
@Immutable
data class IconTabItem(
    val label: String,
    val icon: ImageVector,
    val badgeCount: Int = 0,
)

/** Badge text of an [IconTabBar] item: null when there is nothing to show, capped at "99+". */
fun iconTabBadgeText(count: Int): String? = when {
    count <= 0 -> null
    count > 99 -> "99+"
    else -> count.toString()
}

/** Spoken label of an [IconTabBar] item, e.g. "Quá hạn, 3". */
fun iconTabContentDescription(label: String, badgeCount: Int): String =
    iconTabBadgeText(badgeCount)?.let { "$label, $it" } ?: label

private val ContainerShape = RoundedCornerShape(22.dp)
private val ItemShape = RoundedCornerShape(19.dp)

/**
 * Shared in-screen section switcher (design "E"): a rounded pill holding equal-width items, each an
 * icon above a label of at least 12sp (two lines, never clipped sideways). The selected item sits on a
 * raised surface with SemiBold text. Colors come from [MaterialTheme] only so light/dark both work.
 */
@Composable
fun IconTabBar(
    items: List<IconTabItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(ContainerShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(3.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items.forEachIndexed { index, item ->
            IconTabBarItem(
                item = item,
                selected = index == selectedIndex,
                onClick = { onSelect(index) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun IconTabBarItem(
    item: IconTabItem,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.colorScheme
    val background by animateColorAsState(
        if (selected) colors.surfaceBright else Color.Transparent,
        label = "iconTabBackground",
    )
    val content by animateColorAsState(
        if (selected) colors.onSurface else colors.onSurfaceVariant,
        label = "iconTabContent",
    )
    val description = iconTabContentDescription(item.label, item.badgeCount)
    Column(
        modifier = modifier
            .fillMaxHeight()
            .heightIn(min = 56.dp)
            .shadow(if (selected) 1.dp else 0.dp, ItemShape, clip = false)
            .clip(ItemShape)
            .background(background)
            .selectable(selected = selected, onClick = onClick, role = Role.Tab)
            .semantics { contentDescription = description }
            .padding(horizontal = 4.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(modifier = Modifier.clearAndSetSemantics {}) {
            Icon(
                imageVector = item.icon,
                contentDescription = null,
                tint = content,
                modifier = Modifier.size(24.dp),
            )
            iconTabBadgeText(item.badgeCount)?.let { badge ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 12.dp, y = (-4).dp)
                        .sizeIn(minWidth = 16.dp, minHeight = 16.dp)
                        .background(colors.error, RoundedCornerShape(8.dp))
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        badge,
                        color = colors.onError,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                    )
                }
            }
        }
        Spacer(Modifier.height(2.dp))
        Text(
            item.label,
            modifier = Modifier.clearAndSetSemantics {},
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
            color = content,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
