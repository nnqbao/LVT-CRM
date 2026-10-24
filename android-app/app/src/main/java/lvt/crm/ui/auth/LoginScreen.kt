package lvt.crm.ui.auth

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import lvt.crm.R
import lvt.crm.ui.components.SchoolLogo

@Composable
fun LoginScreen(
    viewModel: LoginViewModel,
) {
    val state by viewModel.uiState.collectAsState()
    var passwordVisible by remember { mutableStateOf(false) }
    val isForgot = state.mode == LoginMode.ForgotPassword
    val context = LocalContext.current
    LaunchedEffect(viewModel) { viewModel.refreshQuickSignIn() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.72f),
                        MaterialTheme.colorScheme.background,
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SchoolLogo(size = 104.dp)
            Spacer(modifier = Modifier.height(18.dp))
            Text(
                "THCS Lê Văn Tám",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.primary,
                textAlign = TextAlign.Center,
            )
            Text(
                "Hệ thống quản lý công tác nội bộ",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp, bottom = 24.dp),
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            ) {
                Column(modifier = Modifier.padding(22.dp)) {
                    Text(
                        if (isForgot) "Quên mật khẩu" else stringResource(R.string.login_title),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        if (isForgot) {
                            "Nhập email tài khoản. Nếu email có trong hệ thống, mật khẩu tạm sẽ được gửi tới hộp thư."
                        } else {
                            "Dùng tài khoản được nhà trường cấp."
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp, bottom = 20.dp),
                    )

                    OutlinedTextField(
                        value = state.email,
                        onValueChange = viewModel::onEmailChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.email)) },
                        leadingIcon = {
                            Icon(Icons.Outlined.MailOutline, contentDescription = null)
                        },
                        singleLine = true,
                        enabled = !state.loading,
                        shape = MaterialTheme.shapes.medium,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Email,
                            imeAction = if (isForgot) ImeAction.Done else ImeAction.Next,
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                if (isForgot) viewModel.requestPasswordReset()
                            },
                        ),
                    )

                    if (!isForgot) {
                        Spacer(modifier = Modifier.height(14.dp))
                        OutlinedTextField(
                            value = state.password,
                            onValueChange = viewModel::onPasswordChange,
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.password)) },
                            leadingIcon = {
                                Icon(Icons.Outlined.Lock, contentDescription = null)
                            },
                            trailingIcon = {
                                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                                    Icon(
                                        if (passwordVisible) {
                                            Icons.Outlined.VisibilityOff
                                        } else {
                                            Icons.Outlined.Visibility
                                        },
                                        contentDescription = if (passwordVisible) {
                                            "Ẩn mật khẩu"
                                        } else {
                                            "Hiện mật khẩu"
                                        },
                                    )
                                }
                            },
                            singleLine = true,
                            enabled = !state.loading,
                            shape = MaterialTheme.shapes.medium,
                            visualTransformation = if (passwordVisible) {
                                VisualTransformation.None
                            } else {
                                PasswordVisualTransformation()
                            },
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Password,
                                imeAction = ImeAction.Done,
                            ),
                            keyboardActions = KeyboardActions(onDone = { viewModel.signIn() }),
                        )
                    }

                    state.error?.let { message ->
                        Surface(
                            color = MaterialTheme.colorScheme.errorContainer,
                            contentColor = MaterialTheme.colorScheme.onErrorContainer,
                            shape = MaterialTheme.shapes.small,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 14.dp),
                        ) {
                            Text(
                                message,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(12.dp),
                            )
                        }
                    }

                    state.info?.let { message ->
                        Surface(
                            color = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            shape = MaterialTheme.shapes.small,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 14.dp),
                        ) {
                            Text(
                                message,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(12.dp),
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                    Button(
                        onClick = {
                            if (isForgot) viewModel.requestPasswordReset() else viewModel.signIn()
                        },
                        enabled = !state.loading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(54.dp),
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        if (state.loading) {
                            CircularProgressIndicator(
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary,
                                modifier = Modifier.size(22.dp),
                            )
                        } else if (isForgot) {
                            Text("Gửi mật khẩu tạm")
                        } else {
                            Text(stringResource(R.string.sign_in))
                            Icon(
                                Icons.AutoMirrored.Outlined.ArrowForward,
                                contentDescription = null,
                                modifier = Modifier.padding(start = 8.dp),
                            )
                        }
                    }

                    if (!isForgot) {
                        QuickSignInButtons(
                            deviceLoginEmail = state.deviceLoginEmail,
                            enabled = !state.loading,
                            onFingerprint = {
                                val activity = context.findFragmentActivity() ?: return@QuickSignInButtons
                                viewModel.signInWithDeviceKey { signature ->
                                    activity.unlockSignature(
                                        signature,
                                        title = "Đăng nhập bằng vân tay",
                                        subtitle = state.deviceLoginEmail.orEmpty(),
                                    )
                                }
                            },
                            onPasskey = {
                                val activity = context.findFragmentActivity() ?: return@QuickSignInButtons
                                viewModel.signInWithPasskey { request -> activity.getPasskeyResponse(request) }
                            },
                        )
                    }

                    TextButton(
                        onClick = {
                            if (isForgot) viewModel.showSignIn() else viewModel.showForgotPassword()
                        },
                        enabled = !state.loading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                    ) {
                        Text(if (isForgot) "Quay lại đăng nhập" else "Quên mật khẩu?")
                    }
                }
            }

            Text(
                "Dữ liệu nội bộ · Chỉ dành cho nhân sự nhà trường",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 18.dp),
            )
            TextButton(
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(context.getString(R.string.privacy_policy_url)))
                    runCatching { context.startActivity(intent) }
                },
            ) {
                Text(stringResource(R.string.privacy_policy))
            }
        }
    }
}

/**
 * "Đăng nhập bằng vân tay" (only when this device holds a fingerprint credential; label names the
 * account) and "Đăng nhập bằng passkey" (Android 9+). Both reuse the password sign-in path.
 */
@Composable
private fun QuickSignInButtons(
    deviceLoginEmail: String?,
    enabled: Boolean,
    onFingerprint: () -> Unit,
    onPasskey: () -> Unit,
) {
    if (deviceLoginEmail != null) {
        OutlinedButton(
            onClick = onFingerprint,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp)
                .height(52.dp),
            shape = MaterialTheme.shapes.medium,
        ) {
            Icon(Icons.Outlined.Fingerprint, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
            Text(
                "Đăng nhập bằng vân tay · $deviceLoginEmail",
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
        }
    }
    if (passkeysSupported) {
        OutlinedButton(
            onClick = onPasskey,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp)
                .height(52.dp),
            shape = MaterialTheme.shapes.medium,
        ) {
            Icon(Icons.Outlined.Key, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
            Text("Đăng nhập bằng passkey")
        }
    }
}
