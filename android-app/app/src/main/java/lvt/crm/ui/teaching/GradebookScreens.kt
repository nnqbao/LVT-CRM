package lvt.crm.ui.teaching

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import lvt.crm.data.teaching.GradeEntry
import lvt.crm.data.teaching.GradeMath
import lvt.crm.data.teaching.GradebookClass
import lvt.crm.data.teaching.StudentRecord
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.homeroom.HomeroomBanner
import lvt.crm.ui.homeroom.HomeroomListRow
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.ListSegment
import lvt.crm.ui.homeroom.toneColors

/** Lớp học › Học bạ: lớp (theo khối) → học sinh → học bạ. */
@Composable
fun GradebookContent(viewModel: GradebookViewModel, state: GradebookUiState) {
    when {
        state.openStudentId != null -> {
            BackHandler { viewModel.closeStudent() }
            StudentRecordContent(viewModel, state)
        }
        state.openClassId != null -> {
            BackHandler { viewModel.closeClass() }
            ClassStudentsContent(viewModel, state)
        }
        else -> GradebookClassesContent(viewModel, state)
    }
    state.editor?.let { editor -> state.record?.let { record -> ScoreEditorDialog(viewModel, record, editor) } }
}

@Composable
private fun GradebookClassesContent(viewModel: GradebookViewModel, state: GradebookUiState) {
    val data = state.classes
    when {
        data == null && state.classesError != null -> {
            Column(Modifier.padding(16.dp)) { ErrorBlock(state.classesError, viewModel::refresh) }
            return
        }
        data == null -> {
            Column(Modifier.padding(16.dp)) { LoadingRow("Đang tải lớp…") }
            return
        }
    }
    val classes = data!!.classes
    if (classes.isEmpty()) {
        StatePanel(
            icon = Icons.Outlined.Groups,
            title = "Bạn chưa phụ trách lớp nào trong năm học này.",
            message = "Học bạ hiện các lớp bạn được xếp lịch dạy hoặc làm giáo viên chủ nhiệm.",
        )
        return
    }
    val groups = gradeGroups(classes)
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item(key = "hint") {
            MutedText("Chọn lớp rồi chọn học sinh để xem và nhập điểm. Bạn nhập điểm cho môn mình dạy ở lớp đó.")
        }
        groups.forEach { (grade, rows) ->
            item(key = "grade-$grade") {
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (grade == null) "Khác" else "Khối $grade", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                    MutedText("${rows.size} lớp")
                }
            }
            if (rows.isEmpty()) {
                item(key = "grade-empty-$grade") { MutedText("Khối này chưa có lớp trong năm học.") }
            }
            itemsIndexed(rows, key = { _, row -> row.id }) { index, row ->
                ListSegment(index, rows.size) {
                    HomeroomListRow(
                        title = row.name,
                        subtitle = gradebookClassMeta(row, state),
                        chips = emptyList(),
                        onClick = { viewModel.openClass(row.id) },
                    )
                }
            }
        }
    }
}

private fun gradeGroups(classes: List<GradebookClass>): List<Pair<Int?, List<GradebookClass>>> {
    val sorted = classes.sortedWith { a, b -> TeachingSchedule.naturalCompare(a.name, b.name) }
    val levels = (listOf(6, 7, 8, 9) + sorted.mapNotNull { it.gradeLevel }).distinct().sorted()
    val groups: List<Pair<Int?, List<GradebookClass>>> = levels.map { level -> level to sorted.filter { it.gradeLevel == level } }
    val others = sorted.filter { it.gradeLevel == null }
    return if (others.isEmpty()) groups else groups + (null to others)
}

private fun gradebookClassMeta(row: GradebookClass, state: GradebookUiState): String {
    val parts = mutableListOf<String>()
    if (row.isHomeroom) parts += "Chủ nhiệm"
    if (row.subjectIds.isNotEmpty()) {
        parts += row.subjectIds.joinToString(", ") { state.catalog?.subjectName(it) ?: "Môn" }
    }
    return parts.joinToString(" · ").ifBlank { "${row.rosterCount} HS" }
}

@Composable
private fun BackRow(label: String, onBack: () -> Unit) {
    TextButton(onClick = onBack, modifier = Modifier.heightIn(min = 48.dp)) {
        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = null, modifier = Modifier.padding(end = 6.dp))
        Text(label)
    }
}

@Composable
private fun ClassStudentsContent(viewModel: GradebookViewModel, state: GradebookUiState) {
    val data = state.students
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item(key = "back") { BackRow("Học bạ", viewModel::closeClass) }
        when {
            data == null && state.studentsError != null -> item(key = "error") { ErrorBlock(state.studentsError, viewModel::refresh) }
            data == null -> item(key = "loading") { LoadingRow("Đang tải học sinh…") }
            else -> {
                item(key = "head") {
                    Column {
                        Text("Học bạ · Năm học ${data.yearName}".uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        Text("Lớp ${data.className}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        MutedText("${data.students.size} học sinh. Bấm vào học sinh để xem điểm.")
                    }
                }
                if (data.students.isEmpty()) {
                    item(key = "empty") { MutedText("Lớp chưa có học sinh.") }
                }
                itemsIndexed(data.students, key = { _, row -> row.id }) { index, row ->
                    ListSegment(index, data.students.size) {
                        HomeroomListRow(
                            title = row.fullName,
                            subtitle = listOfNotNull(
                                "Mã ${row.studentCode}",
                                row.dateOfBirth?.let { "Ngày sinh ${TeachingSchedule.formatDate(it)}" },
                            ).joinToString(" · "),
                            chips = emptyList(),
                            leading = (row.rosterNumber ?: (index + 1)).toString(),
                            onClick = { viewModel.openStudent(row.id) },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StudentRecordContent(viewModel: GradebookViewModel, state: GradebookUiState) {
    val record = state.record
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item(key = "back") { BackRow("Danh sách học sinh", viewModel::closeStudent) }
        if (record == null) {
            item(key = "state") {
                if (state.recordError != null) ErrorBlock(state.recordError, viewModel::refresh) else LoadingRow("Đang tải học bạ…")
            }
            return@LazyColumn
        }
        val selected = record.selectedYear
        item(key = "head") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("HỌC BẠ", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                Text(record.student.fullName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                MutedText(
                    buildString {
                        append("Mã HS ${record.student.studentCode}")
                        record.student.dateOfBirth?.let { append(" · Ngày sinh ${TeachingSchedule.formatDate(it)}") }
                        selected?.let { append(" · Lớp ${it.className} · Năm học ${it.name}") }
                    },
                )
                if (record.canAdd) {
                    Button(onClick = viewModel::startAdd, modifier = Modifier.heightIn(min = 48.dp)) {
                        Icon(Icons.Outlined.Add, contentDescription = null, modifier = Modifier.padding(end = 6.dp))
                        Text("Thêm điểm")
                    }
                }
                state.message?.let { Text(it, color = toneColors(HomeroomTone.Success).text, fontWeight = FontWeight.SemiBold) }
                if (state.recordLoading) LoadingRow("Đang cập nhật…")
                state.recordError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }
        if (record.years.isNotEmpty()) {
            item(key = "years") {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    record.years.forEach { year ->
                        FilterChip(
                            selected = year.id == record.selectedYearId,
                            onClick = { viewModel.selectRecordYear(year.id) },
                            label = {
                                Column(Modifier.padding(vertical = 6.dp)) {
                                    Text("Khối ${year.gradeLevel ?: "—"} · Lớp ${year.className.ifBlank { "—" }}", fontWeight = FontWeight.SemiBold)
                                    Text("Năm học ${year.name}", style = MaterialTheme.typography.bodySmall)
                                    Text("ĐTB năm: ${GradeMath.formatScore(record.yearAverages[year.id])}", style = MaterialTheme.typography.bodySmall)
                                }
                            },
                        )
                    }
                }
            }
        }
        item(key = "notices") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!record.fullView) HomeroomBanner("Bạn đang xem các môn mình dạy học sinh này.", null, HomeroomTone.Info, Icons.Outlined.Info)
                if (selected?.locked == true) HomeroomBanner("Năm học đã khóa — chỉ xem điểm.", null, HomeroomTone.Warning, Icons.Outlined.Lock)
                if (record.testTypes.isEmpty() && record.writableSubjectIds.isNotEmpty()) {
                    HomeroomBanner("Chưa có Loại kiểm tra.", "Quản trị viên thêm tại Thiết lập loại kiểm tra (bản web).", HomeroomTone.Warning, Icons.Outlined.WarningAmber)
                }
            }
        }
        if (record.subjectIds.isEmpty()) {
            item(key = "no-subjects") {
                StatePanel(
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    title = "Chưa có môn học nào trong năm học này.",
                    message = "Môn học hiện theo Lịch dạy của lớp hoặc khi đã có điểm.",
                )
            }
        } else {
            record.subjectIds.forEach { subjectId ->
                item(key = "subject-$subjectId") { SubjectGradeCard(record, subjectId, viewModel::startEdit) }
            }
            item(key = "overall") { OverallCard(record) }
        }
        item(key = "formula") {
            MutedText("ĐTB môn học kỳ = tổng (điểm × hệ số) / tổng hệ số · ĐTB cả năm = (HK I + 2 × HK II) / 3 · ĐTB học kỳ = trung bình các môn.")
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SubjectGradeCard(record: StudentRecord, subjectId: String, onEdit: (GradeEntry) -> Unit) {
    val summary = record.summaryFor(subjectId)
    val locked = record.selectedYear?.locked == true
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(record.subjectName(subjectId), fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
            listOf(1 to summary?.semester1, 2 to summary?.semester2).forEach { (semester, average) ->
                val entries = record.entriesFor(subjectId, semester)
                Row(verticalAlignment = Alignment.Top) {
                    Text(if (semester == 1) "HK I" else "HK II", fontWeight = FontWeight.SemiBold, modifier = Modifier.width(48.dp).padding(top = 6.dp))
                    FlowRow(
                        Modifier.weight(1f),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (entries.isEmpty()) MutedText("—", Modifier.padding(top = 6.dp))
                        entries.forEach { entry -> ScoreChip(entry, enabled = entry.canEdit && !locked) { onEdit(entry) } }
                    }
                    AverageCell(if (semester == 1) "ĐTB HK I" else "ĐTB HK II", average)
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Cả năm", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                AverageCell("Cả năm", summary?.year)
            }
        }
    }
}

@Composable
private fun OverallCard(record: StudentRecord) {
    val tone = toneColors(HomeroomTone.Info)
    Surface(color = tone.background, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("ĐTB các môn", fontWeight = FontWeight.Bold, color = tone.text)
            Row {
                listOf("HK I" to record.semester1, "HK II" to record.semester2, "Cả năm" to record.yearAverage).forEach { (label, value) ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(GradeMath.formatScore(value), fontWeight = FontWeight.ExtraBold, color = tone.text, style = MaterialTheme.typography.titleMedium)
                        Text(label, color = tone.text, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun AverageCell(label: String, value: Double?) {
    Column(
        Modifier.width(64.dp).semantics(mergeDescendants = true) { contentDescription = "$label: ${GradeMath.formatScore(value)}" },
        horizontalAlignment = Alignment.End,
    ) {
        Text(
            GradeMath.formatScore(value),
            fontWeight = FontWeight.Bold,
            color = if (value == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
        Text("ĐTB", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ScoreChip(entry: GradeEntry, enabled: Boolean, onClick: () -> Unit) {
    val label = "${entry.testTypeName} (hệ số ${entry.coefficient}): ${GradeMath.formatScore(entry.score)}"
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = if (enabled) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        contentColor = if (enabled) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .heightIn(min = 36.dp)
            .then(
                if (enabled) {
                    Modifier.clickable(role = Role.Button, onClickLabel = "Sửa điểm", onClick = onClick)
                } else {
                    Modifier
                },
            )
            .semantics(mergeDescendants = true) {
                contentDescription = if (enabled) "Sửa điểm $label" else "$label · ${entry.enteredByName}"
            },
    ) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(GradeMath.formatScore(entry.score), fontWeight = FontWeight.Bold)
            Text(" ${entry.testTypeName}", style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ScoreEditorDialog(viewModel: GradebookViewModel, record: StudentRecord, editor: ScoreEditor) {
    val entry = editor.entry
    val year = record.selectedYear
    AlertDialog(
        onDismissRequest = viewModel::closeEditor,
        title = { Text(if (editor.confirmDelete) "Xóa điểm này?" else if (entry == null) "Thêm điểm" else "Sửa điểm") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                MutedText("${record.student.fullName}${year?.let { " · Lớp ${it.className} · ${it.name}" } ?: ""}")
                if (editor.confirmDelete && entry != null) {
                    Text("${record.subjectName(entry.subjectId)} · ${entry.testTypeName}: ${GradeMath.formatScore(entry.score)}. ĐTB sẽ được tính lại.")
                } else {
                    if (entry != null) {
                        MutedText("${record.subjectName(entry.subjectId)} · nhập bởi ${entry.enteredByName.ifBlank { "—" }} lúc ${formatTimestamp(entry.createdAt)}")
                    } else if (record.writableSubjectIds.size > 1) {
                        FieldLabel("Môn học")
                        OptionPicker(
                            options = record.writableSubjectIds.map { it to record.subjectName(it) },
                            selected = editor.subjectId,
                            enabled = !editor.saving,
                            onSelect = { id -> viewModel.updateEditor { it.copy(subjectId = id) } },
                        )
                    } else {
                        Text("Môn: ${record.subjectName(editor.subjectId)}", fontWeight = FontWeight.SemiBold)
                    }
                    FieldLabel("Loại kiểm tra")
                    val typeOptions = buildList {
                        if (editor.keepsRemovedType && entry != null) add("" to "${entry.testTypeName} (hệ số ${entry.coefficient})")
                        record.testTypes.forEach { add(it.id to "${it.name} (hệ số ${it.coefficient})") }
                    }
                    OptionPicker(
                        options = typeOptions,
                        selected = editor.testTypeId,
                        enabled = !editor.saving,
                        onSelect = { id -> viewModel.updateEditor { it.copy(testTypeId = id) } },
                    )
                    OutlinedTextField(
                        value = editor.scoreText,
                        onValueChange = { text -> viewModel.updateEditor { it.copy(scoreText = text.take(6)) } },
                        label = { Text("Điểm số (0 – 10)") },
                        singleLine = true,
                        enabled = !editor.saving,
                        isError = editor.scoreInvalid,
                        supportingText = {
                            if (editor.scoreInvalid) Text("Điểm từ 0 đến 10, tối đa 2 chữ số thập phân (ví dụ 8,5).")
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    FieldLabel("Học kỳ")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(1 to "Học kỳ I", 2 to "Học kỳ II").forEach { (semester, label) ->
                            FilterChip(
                                selected = editor.semester == semester,
                                onClick = { viewModel.updateEditor { it.copy(semester = semester) } },
                                enabled = !editor.saving,
                                label = { Text(label) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                        }
                    }
                }
                editor.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            if (editor.confirmDelete) {
                Button(
                    onClick = viewModel::deleteEditorEntry,
                    enabled = !editor.saving,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError),
                ) { Text(if (editor.saving) "Đang xóa…" else "Xóa điểm") }
            } else {
                Button(onClick = viewModel::saveEditor, enabled = editor.valid && !editor.saving) {
                    Text(if (editor.saving) "Đang lưu…" else "Lưu")
                }
            }
        },
        dismissButton = {
            Row {
                if (entry != null && !editor.confirmDelete) {
                    TextButton(
                        onClick = { viewModel.updateEditor { it.copy(confirmDelete = true) } },
                        enabled = !editor.saving,
                    ) { Text("Xóa", color = MaterialTheme.colorScheme.error) }
                }
                TextButton(
                    onClick = {
                        if (editor.confirmDelete) viewModel.updateEditor { it.copy(confirmDelete = false) } else viewModel.closeEditor()
                    },
                    enabled = !editor.saving,
                ) { Text("Hủy") }
            }
        },
    )
}

/** Dropdown of (id, label) options with the label above handled by the caller. */
@Composable
private fun OptionPicker(options: List<Pair<String, String>>, selected: String, enabled: Boolean, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val current = options.firstOrNull { it.first == selected }?.second ?: "Chọn"
    Box {
        OutlinedButton(onClick = { expanded = true }, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(current, modifier = Modifier.weight(1f))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (id, label) ->
                DropdownMenuItem(text = { Text(label) }, onClick = {
                    expanded = false
                    onSelect(id)
                })
            }
        }
    }
}
