package lvt.crm.ui.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AdminPanelSettings
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.Business
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.LockReset
import androidx.compose.material.icons.outlined.Brightness6
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import lvt.crm.R
import lvt.crm.data.auth.AuthRepository
import lvt.crm.data.auth.AvatarRepository
import lvt.crm.data.auth.SessionsRepository
import lvt.crm.data.auth.decodeAvatarBitmapForCrop
import lvt.crm.data.auth.prepareAvatarWebP
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import kotlinx.coroutines.launch
import lvt.crm.ui.auth.ChangePasswordScreen
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatusPill
import lvt.crm.ui.components.StatusTone
import lvt.crm.ui.theme.AppearanceMode
import lvt.crm.ui.theme.AppearanceStore
import lvt.crm.ui.components.GuideAnchors

@Composable
fun ProfileScreen(
    name: String,
    email: String,
    role: String,
    departmentName: String?,
    positionName: String?,
    avatarRepository: AvatarRepository,
    authRepository: AuthRepository,
    sessionsRepository: SessionsRepository,
    appearanceStore: AppearanceStore,
    onSignOut: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    var changingPassword by rememberSaveable { mutableStateOf(false) }
    var showingDevices by rememberSaveable { mutableStateOf(false) }
    var showingChangelog by rememberSaveable { mutableStateOf(false) }
    var confirmSignOut by rememberSaveable { mutableStateOf(false) }
    var pickingAppearance by rememberSaveable { mutableStateOf(false) }
    var confirmRemoveAvatar by rememberSaveable { mutableStateOf(false) }
    var avatarBusy by remember { mutableStateOf(false) }
    var avatarError by remember { mutableStateOf<String?>(null) }
    var cropBitmap by remember { mutableStateOf<Bitmap?>(null) }
    val appearance by appearanceStore.mode.collectAsState()
    val avatarBitmap by avatarRepository.bitmap.collectAsState()
    val appVersion = currentAppVersion(LocalContext.current)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        avatarError = null
        scope.launch {
            val loaded = runCatching {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw ConvexException("INVALID_AVATAR_FILE", "INVALID_AVATAR_FILE")
                decodeAvatarBitmapForCrop(bytes)
                    ?: BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw ConvexException("INVALID_AVATAR_FILE", "INVALID_AVATAR_FILE")
            }
            loaded.exceptionOrNull()?.let { failure ->
                val code = (failure as? ConvexException)?.code ?: failure.message
                avatarError = ConvexHttpClient.humanize(code ?: "INVALID_AVATAR_FILE")
                return@launch
            }
            cropBitmap = loaded.getOrNull()
        }
    }

    if (cropBitmap != null) {
        AvatarCropScreen(
            bitmap = cropBitmap!!,
            onCancel = { cropBitmap = null },
            onConfirm = { square ->
                cropBitmap = null
                avatarBusy = true
                avatarError = null
                scope.launch {
                    val result = runCatching {
                        val webp = prepareAvatarWebP(square)
                        avatarRepository.upload(webp).getOrThrow()
                        authRepository.refreshSession()
                    }
                    avatarBusy = false
                    avatarError = result.exceptionOrNull()?.let { failure ->
                        val code = (failure as? ConvexException)?.code ?: failure.message
                        ConvexHttpClient.humanize(code ?: "AVATAR_UPLOAD_FAILED")
                    }
                }
            },
        )
        return
    }

    if (changingPassword) {
        BackHandler { changingPassword = false }
        ChangePasswordScreen(
            title = stringResource(R.string.change_password),
            subtitle = "Đặt mật khẩu mới để bảo vệ tài khoản của bạn.",
            authRepository = authRepository,
            allowCancel = true,
            onDone = { changingPassword = false },
            onCancel = { changingPassword = false },
        )
        return
    }

    if (showingDevices) {
        BackHandler { showingDevices = false }
        DevicesScreen(
            sessionsRepository = sessionsRepository,
            onBack = { showingDevices = false },
        )
        return
    }

    if (showingChangelog) {
        BackHandler { showingChangelog = false }
        ChangelogScreen(
            currentVersion = appVersion,
            onBack = { showingChangelog = false },
        )
        return
    }

    LvtScreen(
        title = stringResource(R.string.nav_profile),
        helpAnchor = GuideAnchors.PROFILE,
        navigationIcon = onBack?.let { back ->
            {
                IconButton(onClick = back) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
                }
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            ) {
            Row(
                modifier = Modifier.padding(20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(68.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary)
                        .clickable(enabled = !avatarBusy) {
                            photoPicker.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    if (avatarBitmap != null) {
                        Image(
                            bitmap = avatarBitmap!!.asImageBitmap(),
                            contentDescription = "Ảnh đại diện",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop,
                        )
                    } else {
                        Text(
                            name.trim().firstOrNull()?.uppercase() ?: "L",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                    if (avatarBusy) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp,
                        )
                    }
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        name.ifBlank { email },
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        email,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.76f),
                        modifier = Modifier.padding(top = 3.dp, bottom = 8.dp),
                    )
                    StatusPill(
                        label = roleLabel(role),
                        tone = StatusTone.Positive,
                    )
                    Text(
                        if (avatarBusy) "Đang cập nhật ảnh…" else "Nhấn ảnh để đổi ảnh đại diện",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.76f),
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    if (avatarBitmap != null) {
                        Text(
                            "Gỡ ảnh đại diện",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .clickable(enabled = !avatarBusy) { confirmRemoveAvatar = true },
                        )
                    }
                    avatarError?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            ListItem(
                headlineContent = { Text("Email đăng nhập") },
                supportingContent = { Text(email) },
                leadingContent = { Icon(Icons.Outlined.Email, contentDescription = null) },
            )
            departmentName?.takeIf { it.isNotBlank() }?.let {
                HorizontalDivider()
                ListItem(
                    headlineContent = { Text("Tổ hoặc phòng") },
                    supportingContent = { Text(it) },
                    leadingContent = { Icon(Icons.Outlined.Business, contentDescription = null) },
                )
            }
            positionName?.takeIf { it.isNotBlank() }?.let {
                HorizontalDivider()
                ListItem(
                    headlineContent = { Text("Chức vụ") },
                    supportingContent = { Text(it) },
                    leadingContent = { Icon(Icons.Outlined.Badge, contentDescription = null) },
                )
            }
            HorizontalDivider()
            ListItem(
                headlineContent = { Text("Vai trò") },
                supportingContent = { Text(roleLabel(role)) },
                leadingContent = { Icon(Icons.Outlined.AdminPanelSettings, contentDescription = null) },
            )
        }

        Spacer(modifier = Modifier.height(12.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            ListItem(
                headlineContent = { Text(stringResource(R.string.devices)) },
                supportingContent = { Text("Phiên đăng nhập trên các thiết bị") },
                leadingContent = { Icon(Icons.Outlined.Devices, contentDescription = null) },
                modifier = Modifier.clickable { showingDevices = true },
            )
            HorizontalDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.change_password)) },
                supportingContent = { Text("Cần mật khẩu hiện tại") },
                leadingContent = { Icon(Icons.Outlined.LockReset, contentDescription = null) },
                modifier = Modifier.clickable { changingPassword = true },
            )
            HorizontalDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.appearance)) },
                supportingContent = { Text(appearance.title) },
                leadingContent = { Icon(Icons.Outlined.Brightness6, contentDescription = null) },
                modifier = Modifier.clickable { pickingAppearance = true },
            )
            HorizontalDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.changelog)) },
                supportingContent = { Text("Xem từng phiên bản đã thêm gì") },
                leadingContent = { Icon(Icons.Outlined.History, contentDescription = null) },
                modifier = Modifier.clickable { showingChangelog = true },
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            ListItem(
                headlineContent = {
                    Text(
                        stringResource(R.string.sign_out),
                        color = MaterialTheme.colorScheme.error,
                    )
                },
                leadingContent = {
                    Icon(
                        Icons.AutoMirrored.Outlined.Logout,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                    )
                },
                modifier = Modifier.clickable { confirmSignOut = true },
            )
        }
        Text(
            "Phiên bản $appVersion",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 10.dp, start = 4.dp),
        )
        Spacer(modifier = Modifier.height(24.dp))
        }
    }

    if (confirmRemoveAvatar) {
        AlertDialog(
            onDismissRequest = { confirmRemoveAvatar = false },
            title = { Text("Gỡ ảnh đại diện?") },
            text = { Text("Hồ sơ sẽ hiện chữ cái tên của bạn cho đến khi bạn chọn ảnh mới.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemoveAvatar = false
                    avatarBusy = true
                    avatarError = null
                    scope.launch {
                        val result = runCatching {
                            avatarRepository.clear().getOrThrow()
                            authRepository.refreshSession()
                        }
                        avatarBusy = false
                        avatarError = result.exceptionOrNull()?.let { failure ->
                            val code = (failure as? ConvexException)?.code ?: failure.message
                            ConvexHttpClient.humanize(code ?: "AVATAR_UPLOAD_FAILED")
                        }
                    }
                }) { Text("Gỡ ảnh") }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemoveAvatar = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text(stringResource(R.string.sign_out_confirm_title)) },
            text = { Text(stringResource(R.string.sign_out_confirm_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmSignOut = false
                    onSignOut()
                }) { Text(stringResource(R.string.confirm)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmSignOut = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    if (pickingAppearance) {
        AlertDialog(
            onDismissRequest = { pickingAppearance = false },
            title = { Text(stringResource(R.string.appearance)) },
            text = {
                Column {
                    AppearanceMode.entries.forEach { mode ->
                        ListItem(
                            headlineContent = { Text(mode.title) },
                            leadingContent = {
                                RadioButton(
                                    selected = mode == appearance,
                                    onClick = {
                                        appearanceStore.set(mode)
                                        pickingAppearance = false
                                    },
                                )
                            },
                            modifier = Modifier.clickable {
                                appearanceStore.set(mode)
                                pickingAppearance = false
                            },
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { pickingAppearance = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
}

private fun roleLabel(role: String): String = when (role) {
    "admin" -> "Quản trị viên"
    "moderator" -> "Điều phối viên"
    else -> "Nhân sự"
}
