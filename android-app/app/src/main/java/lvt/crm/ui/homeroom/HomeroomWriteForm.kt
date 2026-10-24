package lvt.crm.ui.homeroom

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import lvt.crm.data.homeroom.*

/** Contact edit form (student phone / guardian). Attendance dispositions are toggled inline on the class day. */
data class HomeroomForm(val context: DetailContext, val studentId: String? = null, val guardian: Guardian? = null, val contactMode: String = "phone", val initialPhone: String = "")

@Composable fun HomeroomWriteForm(form: HomeroomForm, repository: HomeroomWriteRepository, isCurrent: () -> Boolean, onClear: () -> Unit, onRefresh: () -> Unit, onClose: () -> Unit) {
    var name by remember(form) { mutableStateOf(form.guardian?.fullName ?: "") }
    var phone by remember(form) { mutableStateOf(form.guardian?.phone ?: form.initialPhone) }
    var notes by remember(form) { mutableStateOf(form.guardian?.notes ?: "") }
    var choice by remember(form) { mutableStateOf(form.guardian?.relationship ?: "guardian") }
    var primary by remember(form) { mutableStateOf(form.guardian?.isPrimaryContact ?: false) }
    var busy by remember { mutableStateOf(false) }
    var locked by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmation by remember { mutableStateOf<HomeroomWrite?>(null) }
    val scope = rememberCoroutineScope()
    val latestCurrent by rememberUpdatedState(isCurrent)
    val latestRefresh by rememberUpdatedState(onRefresh)
    val latestClear by rememberUpdatedState(onClear)
    val current = isCurrent()
    LaunchedEffect(current) {
        if (!current && !busy) {
            name = ""; phone = ""; notes = ""; confirmation = null
            if (!locked) message = "Quyền hoặc ngữ cảnh đã thay đổi. Đã xóa nội dung gửi; tải lại trước khi sửa."
            locked = true
        }
    }
    fun submit(write: HomeroomWrite) {
        if (busy || locked) return
        busy = true
        scope.launch {
            try {
                val receipt = repository.submit(write, { latestCurrent() }) { name = ""; phone = ""; notes = ""; locked = true; latestClear() }
                message = receipt.status
                locked = true
                if (latestCurrent()) latestRefresh()
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) {
                message = error.message
                if (isHomeroomWriteDenied(error)) {
                    name = ""; phone = ""; notes = ""; locked = true; latestClear(); latestRefresh()
                } else if (error is WriteUncertain) { locked = true; latestClear() }
            } finally { busy = false }
        }
    }
    AlertDialog(onDismissRequest = { if (!busy) onClose() }, title = { Text(if (form.contactMode == "phone") "Số điện thoại học sinh" else "Người giám hộ") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Máy chủ kiểm tra lại quyền trước khi ghi. Không gửi tin nhắn. Liên hệ chính do máy chủ quyết định.")
            run {
                if (form.contactMode != "phone") {
                    OutlinedTextField(name, { name = it }, label = { Text("Họ tên (1–120)") }, enabled = !busy && !locked)
                    contactRelationships.forEach { value -> FilterChip(selected = choice == value, onClick = { choice = value }, enabled = !busy && !locked, label = { Text(relationshipText(value)) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) }
                    Row { Checkbox(primary, { primary = it }, enabled = !busy && !locked, modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Liên hệ chính" }); Text("Liên hệ chính") }
                    OutlinedTextField(notes, { notes = it }, label = { Text("Ghi chú (tối đa 300)") }, enabled = !busy && !locked)
                }
                OutlinedTextField(phone, { phone = it }, label = { Text("Điện thoại (để trống để xóa)") }, enabled = !busy && !locked)
            }
            message?.let { Text(it) }
            if (busy) CircularProgressIndicator()
            if (locked) OutlinedButton(onClick = { latestRefresh(); onClose() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Chỉ tải lại; không gửi lại") }
            if (form.guardian != null && !locked) OutlinedButton(enabled = !busy, onClick = { confirmation = HomeroomWritePayload.remove(form.context, form.studentId!!, form.guardian.id) }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Xóa người giám hộ") }
        }
    }, confirmButton = { Button(enabled = !busy && !locked, modifier = Modifier.heightIn(min = 48.dp), onClick = {
        try {
            confirmation = if (form.contactMode == "phone") HomeroomWritePayload.studentPhone(form.context, form.studentId!!, phone)
            else HomeroomWritePayload.guardian(form.context, form.studentId!!, form.guardian?.id, choice, name, phone, primary, notes)
        } catch (error: Exception) { message = error.message }
    }) { Text("Kiểm tra và xác nhận") } }, dismissButton = { TextButton(enabled = !busy, onClick = onClose, modifier = Modifier.heightIn(min = 48.dp)) { Text("Đóng") } })
    confirmation?.let { write -> AlertDialog(onDismissRequest = { confirmation = null }, title = { Text("Xác nhận ghi") }, text = { Text(if (write.path.endsWith("removeGuardian")) "Xóa người giám hộ này?" else "Lưu liên hệ này? Liên hệ chính sẽ được tải lại từ máy chủ.") }, confirmButton = { Button(onClick = { confirmation = null; submit(write) }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Xác nhận") } }, dismissButton = { TextButton(onClick = { confirmation = null }) { Text("Quay lại sửa") } }) }
}

internal fun relationshipText(value: String) = mapOf("father" to "Cha", "mother" to "Mẹ", "guardian" to "Người giám hộ", "grandparent" to "Ông/Bà", "sibling" to "Anh/Chị/Em", "other" to "Khác")[value] ?: value
