package lvt.crm.ui.web

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import lvt.crm.data.auth.DeviceAuthRepository
import lvt.crm.data.auth.QuickAuthCancelledException
import lvt.crm.ui.auth.BiometricAvailability
import lvt.crm.ui.auth.biometricAvailability
import lvt.crm.ui.auth.createPasskeyResponse
import lvt.crm.ui.auth.findFragmentActivity
import lvt.crm.ui.auth.passkeysSupported
import lvt.crm.ui.auth.unlockSignature
import lvt.crm.ui.profile.currentAppVersion

/**
 * "Đăng nhập nhanh trên điện thoại này", opened from the web page Thiết bị đăng nhập
 * (`{ type: 'quick-sign-in' }`): vân tay and passkey are phone features, so they stay native
 * (same flows as the former Cá nhân screen).
 */
@Composable
fun QuickSignInSheet(
    userId: String,
    email: String,
    name: String,
    deviceAuthRepository: DeviceAuthRepository,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var fingerprintOn by remember(userId) { mutableStateOf(deviceAuthRepository.isEnabledFor(userId)) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val biometrics = biometricAvailability(context)

    fun setFingerprint(enabled: Boolean) {
        val activity = context.findFragmentActivity() ?: return
        if (busy || userId.isBlank()) return
        busy = true
        message = null
        error = null
        scope.launch {
            val result = if (enabled) {
                deviceAuthRepository.enable(userId, email, name) { signature ->
                    activity.unlockSignature(signature, title = "Bật đăng nhập bằng vân tay", subtitle = email)
                }
            } else {
                deviceAuthRepository.disable()
            }
            fingerprintOn = deviceAuthRepository.isEnabledFor(userId)
            busy = false
            result.exceptionOrNull()?.takeIf { it !is QuickAuthCancelledException }?.let {
                error = it.message ?: "Không bật được đăng nhập bằng vân tay."
            }
            if (result.isSuccess) {
                message = if (enabled) "Đã bật. Lần sau bấm Đăng nhập bằng vân tay ở màn hình đăng nhập." else "Đã tắt đăng nhập bằng vân tay trên máy này."
            }
        }
    }

    fun createPasskey() {
        val activity = context.findFragmentActivity() ?: return
        if (busy) return
        busy = true
        message = null
        error = null
        scope.launch {
            val result = deviceAuthRepository.createPasskey { request -> activity.createPasskeyResponse(request) }
            busy = false
            result.exceptionOrNull()?.takeIf { it !is QuickAuthCancelledException }?.let {
                error = it.message ?: "Không tạo được passkey."
            }
            if (result.isSuccess) message = "Đã tạo passkey. Lần sau bấm Đăng nhập bằng passkey ở màn hình đăng nhập."
        }
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Đăng nhập nhanh trên điện thoại này") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val canToggle = !busy && (fingerprintOn || biometrics == BiometricAvailability.Available)
                ListItem(
                    headlineContent = { Text("Đăng nhập bằng vân tay") },
                    supportingContent = {
                        Text(
                            when {
                                fingerprintOn -> "Đang bật trên máy này"
                                biometrics.message != null -> biometrics.message
                                else -> "Lần sau đăng nhập không cần nhập mật khẩu"
                            },
                        )
                    },
                    leadingContent = { Icon(Icons.Outlined.Fingerprint, contentDescription = null) },
                    trailingContent = { Switch(checked = fingerprintOn, onCheckedChange = null, enabled = canToggle) },
                    modifier = Modifier.toggleable(
                        value = fingerprintOn,
                        enabled = canToggle,
                        role = Role.Switch,
                        onValueChange = { setFingerprint(it) },
                    ),
                )
                if (passkeysSupported) {
                    HorizontalDivider()
                    ListItem(
                        headlineContent = { Text("Tạo passkey") },
                        supportingContent = { Text("Đăng nhập bằng khóa màn hình của máy, không cần mật khẩu") },
                        leadingContent = { Icon(Icons.Outlined.Key, contentDescription = null) },
                        trailingContent = {
                            if (busy) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        },
                        modifier = Modifier.clickable(enabled = !busy) { createPasskey() },
                    )
                }
                message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }
                error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
                Text(
                    "Ứng dụng phiên bản ${currentAppVersion(context)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
        },
        confirmButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Đóng") } },
    )
}
