package lvt.crm.ui.homeroom

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate

internal data class ToneColors(val text: Color, val background: Color)

/** DESIGN.md status colors (homeroom --hr-* palette) with readable dark-mode variants. */
@Composable
internal fun toneColors(tone: HomeroomTone): ToneColors {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    return when (tone) {
        HomeroomTone.Success -> if (dark) ToneColors(Color(0xFF6FD3BE), Color(0xFF10382F)) else ToneColors(Color(0xFF0E7363), Color(0xFFE3F4EF))
        HomeroomTone.Warning -> if (dark) ToneColors(Color(0xFFF2C46B), Color(0xFF3D2C0B)) else ToneColors(Color(0xFF7A4B07), Color(0xFFFDF1D8))
        HomeroomTone.Danger -> if (dark) ToneColors(Color(0xFFFF9C8A), Color(0xFF43201A)) else ToneColors(Color(0xFFB23A27), Color(0xFFFBE5DF))
        HomeroomTone.Neutral -> if (dark) ToneColors(Color(0xFFB7C3CE), Color(0xFF2A3138)) else ToneColors(Color(0xFF5A6B7C), Color(0xFFEEF2F5))
        HomeroomTone.Info -> if (dark) ToneColors(Color(0xFF8DBDF0), Color(0xFF16304A)) else ToneColors(Color(0xFF28639A), Color(0xFFE4EEF8))
    }
}

@Composable
internal fun StatTiles(stats: List<HomeroomStat>, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        stats.forEach { stat ->
            val colors = toneColors(stat.tone)
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.background)
                    .padding(vertical = 10.dp, horizontal = 4.dp)
                    .semantics(mergeDescendants = true) {},
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stat.value, color = colors.text, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp, maxLines = 1)
                Text(stat.label, color = colors.text, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
internal fun StatusChip(chip: HomeroomChip) {
    val colors = toneColors(chip.tone)
    Text(
        chip.text,
        color = colors.text,
        fontWeight = FontWeight.Bold,
        fontSize = 12.sp,
        maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(colors.background)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

/** Two-line list row: title, one muted subtitle, status chips on the right, optional chevron. */
@Composable
internal fun HomeroomListRow(
    title: String,
    subtitle: String?,
    chips: List<HomeroomChip>,
    leading: String? = null,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (leading != null) {
            Text(leading, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp, modifier = Modifier.widthIn(min = 22.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (!subtitle.isNullOrBlank()) {
                Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        chips.forEach { StatusChip(it) }
        if (onClick != null) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
        }
    }
}

/** "‹ Thứ Sáu, 09/10 ›": arrows move one day, tapping the label opens the date picker. */
@Composable
internal fun DayNavigator(date: String, onDate: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onDate(HomeroomPresentation.shiftDay(date, -1)) }) {
            Icon(Icons.Outlined.ChevronLeft, contentDescription = "Ngày trước")
        }
        TextButton(
            onClick = {
                val current = runCatching { LocalDate.parse(date) }.getOrDefault(LocalDate.now())
                DatePickerDialog(context, { _, year, month, day -> onDate(LocalDate.of(year, month + 1, day).toString()) }, current.year, current.monthValue - 1, current.dayOfMonth).show()
            },
            modifier = Modifier.weight(1f).heightIn(min = 48.dp).semantics { contentDescription = "Chọn ngày điểm danh, đang chọn ${HomeroomPresentation.dayTitle(date)}" },
        ) {
            Text(HomeroomPresentation.dayTitle(date), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurface)
        }
        IconButton(onClick = { onDate(HomeroomPresentation.shiftDay(date, 1)) }) {
            Icon(Icons.Outlined.ChevronRight, contentDescription = "Ngày sau")
        }
    }
}

@Composable
internal fun HomeroomBanner(title: String, message: String?, tone: HomeroomTone, icon: ImageVector) {
    val colors = toneColors(tone)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.background)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = colors.text, modifier = Modifier.size(26.dp))
        Column {
            Text(title, color = colors.text, fontWeight = FontWeight.Bold)
            if (!message.isNullOrBlank()) Text(message, color = colors.text, style = MaterialTheme.typography.bodySmall)
        }
    }
}

/** Rows of one list share a surface: rounded top on the first, rounded bottom on the last, hairline between. */
@Composable
internal fun ListSegment(index: Int, count: Int, content: @Composable () -> Unit) {
    val top = if (index == 0) 16.dp else 0.dp
    val bottom = if (index == count - 1) 16.dp else 0.dp
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom))
            .background(MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        if (index > 0) androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        content()
    }
}
