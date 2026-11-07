package lvt.crm.ui.teaching

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import lvt.crm.data.homeroom.SchoolYear
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.toneColors

/** Five tappable stars (radio group). Each star announces "n sao"; gold is backed by the label text. */
@Composable
fun StarRatingInput(rating: Int, enabled: Boolean, onRate: (Int) -> Unit, modifier: Modifier = Modifier) {
    val gold = toneColors(HomeroomTone.Warning).text
    Row(modifier.selectableGroup(), verticalAlignment = Alignment.CenterVertically) {
        (1..5).forEach { value ->
            val filled = value <= rating
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .selectable(selected = rating == value, enabled = enabled, role = Role.RadioButton) { onRate(value) }
                    .semantics { contentDescription = "$value sao" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (filled) Icons.Filled.Star else Icons.Outlined.StarOutline,
                    contentDescription = null,
                    tint = if (filled) gold else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(34.dp),
                )
            }
        }
        Text(
            if (rating in 1..5) "$rating/5" else "Chưa chọn",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 6.dp),
        )
    }
}

/** Read-only stars, announced as "n trên 5 sao". */
@Composable
fun StaticStars(rating: Int, modifier: Modifier = Modifier) {
    val gold = toneColors(HomeroomTone.Warning).text
    Row(modifier.clearAndSetSemantics { contentDescription = TeachingPresentation.starsLabel(rating) }) {
        (1..5).forEach { value ->
            Icon(
                if (value <= rating) Icons.Filled.Star else Icons.Outlined.StarOutline,
                contentDescription = null,
                tint = if (value <= rating) gold else MaterialTheme.colorScheme.outline,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
fun YearSelector(years: List<SchoolYear>, selectedYearId: String?, onYear: (String) -> Unit, modifier: Modifier = Modifier) {
    if (years.isEmpty()) return
    var expanded by remember { mutableStateOf(false) }
    val selected = years.firstOrNull { it.id == selectedYearId }
    Box(modifier) {
        TextButton(onClick = { expanded = true }, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("Năm học ${selected?.name ?: "—"}", fontWeight = FontWeight.SemiBold)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            years.forEach { year ->
                DropdownMenuItem(
                    text = { Text(if (year.active) "${year.name} (mặc định)" else year.name) },
                    onClick = {
                        expanded = false
                        onYear(year.id)
                    },
                )
            }
        }
    }
}

/** "‹ label ›" stepper used by Sổ đầu bài weeks and Lịch dạy periods. */
@Composable
fun PeriodStepper(
    label: String,
    canPrevious: Boolean,
    canNext: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    previousLabel: String,
    nextLabel: String,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onPrevious, enabled = canPrevious) {
            Icon(Icons.Outlined.ChevronLeft, contentDescription = previousLabel)
        }
        Text(label, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        IconButton(onClick = onNext, enabled = canNext) {
            Icon(Icons.Outlined.ChevronRight, contentDescription = nextLabel)
        }
    }
}

/** Titled card section (web hr-panel). */
@Composable
fun TeachingCard(
    eyebrow: String?,
    title: String,
    subtitle: String? = null,
    action: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    if (eyebrow != null) {
                        Text(eyebrow.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    if (subtitle != null) {
                        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                action?.invoke()
            }
            content()
        }
    }
}

@Composable
fun LoadingRow(label: String) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun ErrorBlock(message: String, onRetry: (() -> Unit)?) {
    val colors = toneColors(HomeroomTone.Danger)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = colors.text)
            Text(message, color = colors.text)
        }
        if (onRetry != null) Button(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp)) { Text("Thử lại") }
    }
}

@Composable
fun MutedText(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}
