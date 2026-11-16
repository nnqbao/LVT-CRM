package lvt.crm.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.LockReset
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import lvt.crm.data.auth.AuthRepository
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient

@Composable
fun ChangePasswordScreen(
    title: String,
    subtitle: String,
    authRepository: AuthRepository,
    allowCancel: Boolean,
    onDone: () -> Unit,
    onCancel: (() -> Unit)? = null,
) {
    // Keep password material out of saved instance state; only the enclosing route is restorable.
    var currentPassword by remember { mutableStateOf("") }
    var currentVisible by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var confirmationVisible by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.LockReset,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(34.dp),
                )
            }
            Spacer(modifier = Modifier.height(18.dp))
            Text(
                title,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 6.dp, bottom = 22.dp),
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
            ) {
                Column(modifier = Modifier.padding(20.dp)) {
                    if (allowCancel) {
                        PasswordField(
                            value = currentPassword,
                            onValueChange = {
                                currentPassword = it
                                error = null
                                success = null
                            },
                            label = "Mật khẩu hiện tại",
                            visible = currentVisible,
                            onToggleVisibility = { currentVisible = !currentVisible },
                            enabled = !loading,
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                    }
                    PasswordField(
                        value = password,
                        onValueChange = {
                            password = it
                            error = null
                            success = null
                        },
                        label = "Mật khẩu mới",
                        visible = passwordVisible,
                        onToggleVisibility = { passwordVisible = !passwordVisible },
                        enabled = !loading,
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    PasswordField(
                        value = confirmation,
                        onValueChange = {
                            confirmation = it
                            error = null
                            success = null
                        },
                        label = "Xác nhận mật khẩu",
                        visible = confirmationVisible,
                        onToggleVisibility = {
                            confirmationVisible = !confirmationVisible
                        },
                        enabled = !loading,
                    )

                    Surface(
                        color = if (password.length >= 8) {
                            MaterialTheme.colorScheme.secondaryContainer
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant
                        },
                        contentColor = if (password.length >= 8) {
                            MaterialTheme.colorScheme.onSecondaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 14.dp),
                    ) {
                        Text(
                            if (password.length >= 8) {
                                "Mật khẩu đã đạt yêu cầu tối thiểu."
                            } else {
                                "Mật khẩu cần tối thiểu 8 ký tự."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(12.dp),
                        )
                    }

                    FeedbackMessage(error = error, success = success)

                    Spacer(modifier = Modifier.height(20.dp))
                    Button(
                        onClick = {
                            when {
                                allowCancel && currentPassword.isBlank() ->
                                    error = "Vui lòng nhập mật khẩu hiện tại."
                                password.length < 8 ->
                                    error = "Mật khẩu phải có ít nhất 8 ký tự."
                                password != confirmation ->
                                    error = "Xác nhận mật khẩu không khớp."
                                else -> scope.launch {
                                    loading = true
                                    error = null
                                    success = null
                                    val result = authRepository.changePassword(
                                        password,
                                        currentPassword = currentPassword.takeIf { allowCancel },
                                    )
                                    loading = false
                                    result.fold(
                                        onSuccess = {
                                            password = ""
                                            confirmation = ""
                                            currentPassword = ""
                                            passwordVisible = false
                                            confirmationVisible = false
                                            success = "Đã đổi mật khẩu."
                                            onDone()
                                        },
                                        onFailure = { failure ->
                                            error = connectionErrorMessage(failure) ?: when (failure) {
                                                is ConvexException -> failure.message
                                                else -> ConvexHttpClient.humanize(
                                                    failure.message
                                                        ?: "PASSWORD_CHANGE_FAILED",
                                                )
                                            }
                                        },
                                    )
                                }
                            }
                        },
                        enabled = !loading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        if (loading) {
                            CircularProgressIndicator(
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary,
                                modifier = Modifier.size(21.dp),
                            )
                        } else {
                            Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                            Text("Lưu mật khẩu", modifier = Modifier.padding(start = 8.dp))
                        }
                    }

                    if (allowCancel && onCancel != null) {
                        Spacer(modifier = Modifier.height(10.dp))
                        FilledTonalButton(
                            onClick = onCancel,
                            enabled = !loading,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(50.dp),
                            shape = MaterialTheme.shapes.medium,
                        ) {
                            Text("Hủy")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    visible: Boolean,
    onToggleVisibility: () -> Unit,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        leadingIcon = {
            Icon(Icons.Outlined.LockReset, contentDescription = null)
        },
        trailingIcon = {
            IconButton(onClick = onToggleVisibility) {
                Icon(
                    if (visible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                    contentDescription = if (visible) "Ẩn mật khẩu" else "Hiện mật khẩu",
                )
            }
        },
        singleLine = true,
        enabled = enabled,
        shape = MaterialTheme.shapes.medium,
        visualTransformation = if (visible) {
            VisualTransformation.None
        } else {
            PasswordVisualTransformation()
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
    )
}

@Composable
private fun FeedbackMessage(
    error: String?,
    success: String?,
) {
    val message = error ?: success ?: return
    val isError = error != null
    Surface(
        color = if (isError) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.secondaryContainer
        },
        contentColor = if (isError) {
            MaterialTheme.colorScheme.onErrorContainer
        } else {
            MaterialTheme.colorScheme.onSecondaryContainer
        },
        shape = MaterialTheme.shapes.small,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp),
    ) {
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(12.dp),
        )
    }
}
