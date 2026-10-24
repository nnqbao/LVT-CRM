package lvt.crm.data.auth

import java.security.Signature
import java.util.Base64
import java.util.UUID
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.convex.TeachingAuthErrorMessages
import org.json.JSONObject

/** The person dismissed the fingerprint / passkey sheet: never shown as an error. */
class QuickAuthCancelledException : Exception("QUICK_AUTH_CANCELLED")

/** The biometric-bound key no longer works (new fingerprint enrolled, lock screen removed…). */
class DeviceKeyInvalidatedException(cause: Throwable? = null) : Exception("DEVICE_KEY_INVALIDATED", cause)

/** Fingerprint sign-in of this device; never contains a password. */
data class SavedDeviceCredential(
    val credentialId: String,
    val userId: String,
    val email: String,
    val name: String,
    /** Android Keystore alias of the P-256 key bound to this credential. */
    val keyAlias: String,
)

interface DeviceCredentialStore {
    fun load(): SavedDeviceCredential?
    fun save(credential: SavedDeviceCredential)
    fun clear()
}

/** Biometric-bound P-256 signing keys (AndroidKeyStore in the app, fakes in tests). */
interface DeviceKeys {
    fun exists(alias: String): Boolean

    /** Creates the key and returns its public key as X.509 SubjectPublicKeyInfo (DER). */
    fun create(alias: String): ByteArray

    /** A SHA256withECDSA signature initialised for signing; throws [DeviceKeyInvalidatedException]. */
    fun signer(alias: String): Signature

    fun delete(alias: String)
}

/** The few Convex calls quick sign-in needs (lets tests run without HTTP). */
interface DeviceAuthApi {
    suspend fun mutation(path: String, args: JSONObject, authenticated: Boolean): JSONObject
    suspend fun action(path: String, args: JSONObject, authenticated: Boolean): JSONObject
}

fun ConvexHttpClient.asDeviceAuthApi(): DeviceAuthApi = object : DeviceAuthApi {
    override suspend fun mutation(path: String, args: JSONObject, authenticated: Boolean): JSONObject =
        this@asDeviceAuthApi.mutation(path, args, authenticated)

    override suspend fun action(path: String, args: JSONObject, authenticated: Boolean): JSONObject =
        this@asDeviceAuthApi.action(path, args, authenticated)
}

/** Shows the biometric prompt for an initialised signature and returns it once unlocked. */
typealias BiometricUnlock = suspend (Signature) -> Signature

/** Runs Credential Manager with a request JSON and returns the response JSON. */
typealias PasskeyCeremony = suspend (String) -> String

/** What the login screen needs for quick sign-in. */
interface QuickSignInGateway {
    /** Email of the account whose fingerprint sign-in is set up on this device, if any. */
    fun savedDeviceEmail(): String?
    suspend fun signInWithDeviceKey(unlock: BiometricUnlock): Result<UserSession>
    suspend fun signInWithPasskey(ceremony: PasskeyCeremony): Result<UserSession>
}

/**
 * Vân tay (device key) and passkey sign-in (docs/native-teaching-auth-contract.md §2–3).
 * Tokens always go through [SignInGateway.signInWithProvider], i.e. the password sign-in path.
 */
class DeviceAuthRepository(
    private val api: DeviceAuthApi,
    private val auth: SignInGateway,
    private val store: DeviceCredentialStore,
    private val keys: DeviceKeys,
    private val deviceName: String,
    private val newAlias: () -> String = { "lvt_crm_device_key_" + UUID.randomUUID().toString().replace("-", "") },
) : QuickSignInGateway {

    /** The saved credential, only while its key still exists in the keystore. */
    fun savedCredential(): SavedDeviceCredential? {
        val saved = store.load() ?: return null
        if (!keys.exists(saved.keyAlias)) {
            store.clear()
            return null
        }
        return saved
    }

    override fun savedDeviceEmail(): String? = savedCredential()?.email

    /** Switch state for the signed-in account: another account's credential never shows as on. */
    fun isEnabledFor(userId: String): Boolean = savedCredential()?.userId == userId

    suspend fun enable(userId: String, email: String, name: String, unlock: BiometricUnlock): Result<Unit> {
        val previous = store.load()
        val alias = newAlias()
        return try {
            val publicKey = keys.create(alias)
            val challenge = api.mutation("deviceAuth:deviceRegisterChallenge", JSONObject(), true)
            val challengeId = challenge.getString("challengeId")
            val signature = sign(alias, unlock, deviceSignedMessage("device_register", challengeId, challenge.getString("challenge")))
            val args = JSONObject()
                .put("challengeId", challengeId)
                .put("publicKey", base64(publicKey))
                .put("signature", base64(signature))
                .put("deviceName", deviceName)
                .put("platform", "android")
            previous?.takeIf { it.userId == userId }?.let { args.put("replaceCredentialId", it.credentialId) }
            val result = api.action("deviceAuth:registerDeviceKey", args, true)
            val credentialId = result.getString("credentialId")
            store.save(SavedDeviceCredential(credentialId, userId, email, name, alias))
            if (previous != null && previous.keyAlias != alias) runCatching { keys.delete(previous.keyAlias) }
            Result.success(Unit)
        } catch (e: Exception) {
            runCatching { keys.delete(alias) }
            Result.failure(e.asQuickAuthFailure())
        }
    }

    /** Turns fingerprint sign-in off: revoke on the server (best-effort), then delete the local key. */
    suspend fun disable(): Result<Unit> {
        val saved = store.load() ?: return Result.success(Unit)
        runCatching {
            api.mutation("deviceAuth:removeMine", JSONObject().put("credentialId", saved.credentialId), true)
        }
        forget(saved)
        return Result.success(Unit)
    }

    override suspend fun signInWithDeviceKey(unlock: BiometricUnlock): Result<UserSession> {
        val saved = savedCredential() ?: return Result.failure(invalidCredential())
        return try {
            val challenge = api.mutation("deviceAuth:deviceLoginChallenge", JSONObject(), false)
            val challengeId = challenge.getString("challengeId")
            val signature = sign(saved.keyAlias, unlock, deviceSignedMessage("device_login", challengeId, challenge.getString("challenge")))
            val result = auth.signInWithProvider(
                "device-key",
                JSONObject()
                    .put("credentialId", saved.credentialId)
                    .put("challengeId", challengeId)
                    .put("signature", base64(signature)),
            )
            result.exceptionOrNull()?.let { failure ->
                if (failure.isInvalidCredential()) {
                    forget(saved)
                    return Result.failure(invalidCredential())
                }
            }
            result
        } catch (e: DeviceKeyInvalidatedException) {
            forget(saved)
            Result.failure(invalidCredential())
        } catch (e: Exception) {
            if (e.isInvalidCredential()) forget(saved)
            Result.failure(e.asQuickAuthFailure())
        }
    }

    override suspend fun signInWithPasskey(ceremony: PasskeyCeremony): Result<UserSession> = try {
        val options = api.action("deviceAuth:passkeyLoginOptions", JSONObject(), false)
        val response = ceremony(options.getString("options"))
        auth.signInWithProvider(
            "passkey",
            JSONObject().put("challengeId", options.getString("challengeId")).put("response", response),
        )
    } catch (e: Exception) {
        Result.failure(e.asQuickAuthFailure())
    }

    /** Profile → "Tạo passkey" (signed in). */
    suspend fun createPasskey(ceremony: PasskeyCeremony): Result<Unit> = try {
        val options = api.action("deviceAuth:passkeyRegistrationOptions", JSONObject(), true)
        val response = ceremony(options.getString("options"))
        api.action(
            "deviceAuth:registerPasskey",
            JSONObject()
                .put("challengeId", options.getString("challengeId"))
                .put("response", response)
                .put("deviceName", deviceName)
                .put("platform", "android"),
            true,
        )
        Result.success(Unit)
    } catch (e: Exception) {
        Result.failure(e.asQuickAuthFailure())
    }

    private suspend fun sign(alias: String, unlock: BiometricUnlock, message: String): ByteArray {
        val unlocked = unlock(keys.signer(alias))
        unlocked.update(message.toByteArray(Charsets.UTF_8))
        return unlocked.sign()
    }

    private fun forget(saved: SavedDeviceCredential) {
        runCatching { keys.delete(saved.keyAlias) }
        if (store.load()?.credentialId == saved.credentialId) store.clear()
    }

    private fun invalidCredential() = ConvexException(
        TeachingAuthErrorMessages.DEVICE_CREDENTIAL_INVALID,
        ConvexHttpClient.humanize(TeachingAuthErrorMessages.DEVICE_CREDENTIAL_INVALID),
    )

    private fun Throwable.isInvalidCredential(): Boolean =
        (this as? ConvexException)?.code == TeachingAuthErrorMessages.DEVICE_CREDENTIAL_INVALID ||
            message.orEmpty().contains(TeachingAuthErrorMessages.DEVICE_CREDENTIAL_INVALID)

    private fun Exception.asQuickAuthFailure(): Exception = when (this) {
        is QuickAuthCancelledException, is ConvexException -> this
        is DeviceKeyInvalidatedException -> invalidCredential()
        else -> ConvexException("QUICK_AUTH_FAILED", message?.takeIf { it.isNotBlank() } ?: "Không xác thực được. Vui lòng thử lại.")
    }

    companion object {
        /** UTF-8 text the device key signs: `lvt-crm:{purpose}:{challengeId}:{challenge}`. */
        fun deviceSignedMessage(purpose: String, challengeId: String, challenge: String): String =
            "lvt-crm:$purpose:$challengeId:$challenge"

        fun base64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
    }
}
