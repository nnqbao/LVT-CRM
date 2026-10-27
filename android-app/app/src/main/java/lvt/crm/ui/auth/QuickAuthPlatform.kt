package lvt.crm.ui.auth

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.fragment.app.FragmentActivity
import java.security.Signature
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import lvt.crm.data.auth.DeviceKeyInvalidatedException
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.auth.QuickAuthCancelledException

/** Whether this device can hold a fingerprint (strong biometric) sign-in key. */
enum class BiometricAvailability(val message: String?) {
    Available(null),
    NoneEnrolled("Máy chưa cài vân tay. Thêm vân tay trong Cài đặt của máy rồi bật lại."),
    NoHardware("Máy không có cảm biến sinh trắc học đủ mạnh để đăng nhập."),
    Unavailable("Cảm biến vân tay đang không dùng được. Thử lại sau."),
    OsTooOld("Cần Android 9 trở lên để đăng nhập bằng vân tay."),
}

/**
 * Android 9+ only: below that BiometricPrompt falls back to an AppCompat dialog, which this
 * (non-AppCompat) activity theme cannot host.
 */
fun biometricAvailability(context: Context): BiometricAvailability =
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) BiometricAvailability.OsTooOld
    else when (BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG)) {
        BiometricManager.BIOMETRIC_SUCCESS -> BiometricAvailability.Available
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> BiometricAvailability.NoneEnrolled
        BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE,
        BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED,
        BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
        -> BiometricAvailability.NoHardware
        else -> BiometricAvailability.Unavailable
    }

/** Passkeys through Credential Manager need Android 9+ (Play services provider below Android 14). */
val passkeysSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}

/**
 * Biometric prompt bound to [signature] (CryptoObject): returns the unlocked signature, throws
 * [QuickAuthCancelledException] when dismissed.
 */
suspend fun FragmentActivity.unlockSignature(signature: Signature, title: String, subtitle: String): Signature =
    suspendCancellableCoroutine { continuation ->
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    val unlocked = result.cryptoObject?.signature
                    if (!continuation.isActive) return
                    if (unlocked == null) {
                        continuation.resumeWithException(DeviceKeyInvalidatedException())
                    } else {
                        continuation.resume(unlocked)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (!continuation.isActive) return
                    val cancelled = errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_CANCELED
                    continuation.resumeWithException(
                        when {
                            cancelled -> QuickAuthCancelledException()
                            errorCode == BiometricPrompt.ERROR_NO_BIOMETRICS ||
                                errorCode == BiometricPrompt.ERROR_HW_NOT_PRESENT ->
                                DeviceKeyInvalidatedException()
                            else -> ConvexException("BIOMETRIC_ERROR", errString.toString().ifBlank { "Không xác thực được vân tay." })
                        },
                    )
                }
                // onAuthenticationFailed: the prompt stays open for another try.
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setNegativeButtonText("Hủy")
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(signature))
        continuation.invokeOnCancellation { runCatching { prompt.cancelAuthentication() } }
    }

/** Credential Manager: create a passkey from PublicKeyCredentialCreationOptionsJSON. */
suspend fun FragmentActivity.createPasskeyResponse(requestJson: String): String {
    val manager = CredentialManager.create(this)
    return try {
        val response = manager.createCredential(this, CreatePublicKeyCredentialRequest(requestJson))
        (response as? CreatePublicKeyCredentialResponse)?.registrationResponseJson
            ?: throw ConvexException("PASSKEY_CREATE_FAILED", "Không tạo được passkey trên máy này.")
    } catch (e: CreateCredentialCancellationException) {
        throw QuickAuthCancelledException()
    } catch (e: CreateCredentialException) {
        throw ConvexException("PASSKEY_CREATE_FAILED", "Không tạo được passkey trên máy này. Kiểm tra máy đã bật khóa màn hình và Trình quản lý mật khẩu của Google.")
    }
}

/** Credential Manager: sign in with a discoverable passkey (PublicKeyCredentialRequestOptionsJSON). */
suspend fun FragmentActivity.getPasskeyResponse(requestJson: String): String {
    val manager = CredentialManager.create(this)
    return try {
        val result = manager.getCredential(this, GetCredentialRequest(listOf(GetPublicKeyCredentialOption(requestJson))))
        (result.credential as? PublicKeyCredential)?.authenticationResponseJson
            ?: throw ConvexException("PASSKEY_GET_FAILED", "Không đọc được passkey.")
    } catch (e: GetCredentialCancellationException) {
        throw QuickAuthCancelledException()
    } catch (e: NoCredentialException) {
        throw ConvexException(
            "PASSKEY_NOT_FOUND",
            "Máy này chưa có passkey của ứng dụng. Đăng nhập bằng mật khẩu rồi tạo passkey trong Cá nhân.",
        )
    } catch (e: GetCredentialException) {
        throw ConvexException("PASSKEY_GET_FAILED", "Không đăng nhập được bằng passkey. Vui lòng thử lại.")
    }
}
