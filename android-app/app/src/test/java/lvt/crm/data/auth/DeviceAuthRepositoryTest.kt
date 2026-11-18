package lvt.crm.data.auth

import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import kotlinx.coroutines.test.runTest
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceAuthRepositoryTest {
    private val unlock: BiometricUnlock = { it }

    @Test
    fun enableRegistersSpkiKeyWithValidSignatureAndStoresNoPassword() = runTest {
        val env = Env()
        val result = env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)

        assertTrue(result.isSuccess)
        val register = env.api.calls.single { it.first == "deviceAuth:registerDeviceKey" }.second
        assertEquals("android", register.getString("platform"))
        assertEquals("Pixel 8", register.getString("deviceName"))
        assertFalse(register.has("replaceCredentialId"))
        val publicKey = Base64.getDecoder().decode(register.getString("publicKey"))
        assertEquals("SPKI (91 bytes) for P-256", 91, publicKey.size)
        val verifier = Signature.getInstance("SHA256withECDSA").apply {
            initVerify(KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicKey)))
            update("lvt-crm:device_register:reg-1:reg-challenge".toByteArray(Charsets.UTF_8))
        }
        assertTrue(verifier.verify(Base64.getDecoder().decode(register.getString("signature"))))
        val saved = env.store.load()!!
        assertEquals(SavedDeviceCredential("cred-1", "u1", "gv@lvt.vn", "Cô A", "alias-1"), saved)
        assertTrue(env.repository.isEnabledFor("u1"))
        assertFalse("another account never shows as on", env.repository.isEnabledFor("u2"))
        assertEquals("gv@lvt.vn", env.repository.savedDeviceEmail())
    }

    @Test
    fun reEnablingTheSameAccountReplacesTheOldCredential() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        val second = env.api.calls.filter { it.first == "deviceAuth:registerDeviceKey" }[1].second
        assertEquals("cred-1", second.getString("replaceCredentialId"))
        assertFalse("old key deleted", env.keys.exists("alias-1"))
        assertTrue(env.keys.exists("alias-2"))

        env.repository.enable("u2", "khac@lvt.vn", "Thầy B", unlock)
        val third = env.api.calls.filter { it.first == "deviceAuth:registerDeviceKey" }[2].second
        assertFalse("never replaces another account's credential", third.has("replaceCredentialId"))
        assertTrue(env.repository.isEnabledFor("u2"))
        assertFalse(env.repository.isEnabledFor("u1"))
    }

    @Test
    fun cancellingTheEnablePromptKeepsThePreviousState() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        val result = env.repository.enable("u1", "gv@lvt.vn", "Cô A") { throw QuickAuthCancelledException() }
        assertTrue(result.exceptionOrNull() is QuickAuthCancelledException)
        assertTrue(env.repository.isEnabledFor("u1"))
        assertFalse("half-created key removed", env.keys.exists("alias-2"))
    }

    @Test
    fun signInSignsTheLoginChallengeAndUsesTheSharedProviderPath() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        val result = env.repository.signInWithDeviceKey(unlock)

        assertTrue(result.isSuccess)
        assertEquals(false, env.api.authenticated["deviceAuth:deviceLoginChallenge"])
        val (provider, params) = env.gateway.calls.single()
        assertEquals("device-key", provider)
        assertEquals("cred-1", params.getString("credentialId"))
        assertEquals("login-1", params.getString("challengeId"))
        val verifier = Signature.getInstance("SHA256withECDSA").apply {
            initVerify(env.keys.pairs.getValue("alias-1").public)
            update("lvt-crm:device_login:login-1:login-challenge".toByteArray(Charsets.UTF_8))
        }
        assertTrue(verifier.verify(Base64.getDecoder().decode(params.getString("signature"))))
    }

    @Test
    fun invalidCredentialFromServerForgetsTheLocalKey() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        env.gateway.result = Result.failure(
            ConvexException("DEVICE_CREDENTIAL_INVALID", ConvexHttpClient.humanize("Uncaught ConvexError: DEVICE_CREDENTIAL_INVALID")),
        )
        val result = env.repository.signInWithDeviceKey(unlock)

        val error = result.exceptionOrNull() as ConvexException
        assertEquals("DEVICE_CREDENTIAL_INVALID", error.code)
        assertTrue(error.message!!.contains("Đăng nhập bằng mật khẩu rồi bật lại"))
        assertNull(env.store.load())
        assertFalse(env.keys.exists("alias-1"))
        assertNull(env.repository.savedDeviceEmail())
    }

    @Test
    fun invalidatedKeyAfterNewFingerprintIsTreatedTheSame() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        env.keys.invalidated += "alias-1"
        val result = env.repository.signInWithDeviceKey(unlock)
        assertEquals("DEVICE_CREDENTIAL_INVALID", (result.exceptionOrNull() as ConvexException).code)
        assertNull(env.store.load())
        assertTrue(env.gateway.calls.isEmpty())
    }

    @Test
    fun cancelledFingerprintPromptKeepsTheCredential() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        val result = env.repository.signInWithDeviceKey { throw QuickAuthCancelledException() }
        assertTrue(result.exceptionOrNull() is QuickAuthCancelledException)
        assertTrue(env.repository.isEnabledFor("u1"))
    }

    @Test
    fun disableRevokesBestEffortAndDeletesTheKey() = runTest {
        val env = Env()
        env.repository.enable("u1", "gv@lvt.vn", "Cô A", unlock)
        env.api.failRemove = true
        assertTrue(env.repository.disable().isSuccess)
        assertEquals("cred-1", env.api.calls.last { it.first == "deviceAuth:removeMine" }.second.getString("credentialId"))
        assertNull(env.store.load())
        assertFalse(env.keys.exists("alias-1"))
    }

    @Test
    fun passkeySignInSendsTheCredentialManagerResponse() = runTest {
        val env = Env()
        var request: String? = null
        val result = env.repository.signInWithPasskey { json ->
            request = json
            """{"id":"pk","type":"public-key"}"""
        }
        assertTrue(result.isSuccess)
        assertEquals("""{"challenge":"abc"}""", request)
        assertEquals(false, env.api.authenticated["deviceAuth:passkeyLoginOptions"])
        val (provider, params) = env.gateway.calls.single()
        assertEquals("passkey", provider)
        assertEquals("pk-login", params.getString("challengeId"))
        assertEquals("""{"id":"pk","type":"public-key"}""", params.getString("response"))
    }

    @Test
    fun createPasskeyRegistersTheResponseAsIs() = runTest {
        val env = Env()
        assertTrue(env.repository.createPasskey { """{"id":"new"}""" }.isSuccess)
        val register = env.api.calls.single { it.first == "deviceAuth:registerPasskey" }.second
        assertEquals("pk-reg", register.getString("challengeId"))
        assertEquals("""{"id":"new"}""", register.getString("response"))
        assertEquals("android", register.getString("platform"))
        val cancelled = env.repository.createPasskey { throw QuickAuthCancelledException() }
        assertTrue(cancelled.exceptionOrNull() is QuickAuthCancelledException)
    }

    private class Env {
        val api = FakeApi()
        val gateway = FakeGateway()
        val store = MemoryStore()
        val keys = SoftwareKeys()
        private var aliasCount = 0
        val repository = DeviceAuthRepository(api, gateway, store, keys, "Pixel 8") { "alias-${++aliasCount}" }
    }

    private class FakeApi : DeviceAuthApi {
        val calls = mutableListOf<Pair<String, JSONObject>>()
        val authenticated = mutableMapOf<String, Boolean>()
        var failRemove = false
        private var credentials = 0

        override suspend fun mutation(path: String, args: JSONObject, authenticated: Boolean): JSONObject {
            calls += path to args
            this.authenticated[path] = authenticated
            return when (path) {
                "deviceAuth:deviceRegisterChallenge" -> JSONObject().put("challengeId", "reg-1").put("challenge", "reg-challenge")
                "deviceAuth:deviceLoginChallenge" -> JSONObject().put("challengeId", "login-1").put("challenge", "login-challenge")
                "deviceAuth:removeMine" -> if (failRemove) throw ConvexException("HTTP_503") else JSONObject()
                else -> error("unexpected $path")
            }
        }

        override suspend fun action(path: String, args: JSONObject, authenticated: Boolean): JSONObject {
            calls += path to args
            this.authenticated[path] = authenticated
            return when (path) {
                "deviceAuth:registerDeviceKey" -> JSONObject().put("credentialId", "cred-${++credentials}")
                "deviceAuth:passkeyLoginOptions" -> JSONObject().put("challengeId", "pk-login").put("options", """{"challenge":"abc"}""")
                "deviceAuth:passkeyRegistrationOptions" -> JSONObject().put("challengeId", "pk-reg").put("options", """{"rp":{"id":"lvt.vscgroup.io.vn"}}""")
                "deviceAuth:registerPasskey" -> JSONObject().put("credentialId", "pk")
                else -> error("unexpected $path")
            }
        }
    }

    private class FakeGateway : SignInGateway {
        val calls = mutableListOf<Pair<String, JSONObject>>()
        var result: Result<UserSession> = Result.success(UserSession("u1", "gv@lvt.vn", "Cô A", "user", "active"))
        override suspend fun signIn(email: String, password: String): Result<UserSession> = error("password not used")
        override suspend fun requestPasswordReset(email: String): Result<Unit> = Result.success(Unit)
        override suspend fun signInWithProvider(provider: String, params: JSONObject): Result<UserSession> {
            calls += provider to params
            return result
        }
    }

    private class MemoryStore : DeviceCredentialStore {
        private var value: SavedDeviceCredential? = null
        override fun load(): SavedDeviceCredential? = value
        override fun save(credential: SavedDeviceCredential) { value = credential }
        override fun clear() { value = null }
    }

    /** Software P-256 keys standing in for AndroidKeyStore. */
    private class SoftwareKeys : DeviceKeys {
        val pairs = mutableMapOf<String, KeyPair>()
        val invalidated = mutableSetOf<String>()
        override fun exists(alias: String): Boolean = alias in pairs
        override fun create(alias: String): ByteArray {
            val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
            pairs[alias] = pair
            return pair.public.encoded
        }
        override fun signer(alias: String): Signature {
            if (alias in invalidated) throw DeviceKeyInvalidatedException()
            val pair = pairs[alias] ?: throw DeviceKeyInvalidatedException()
            return Signature.getInstance("SHA256withECDSA").apply { initSign(pair.private) }
        }
        override fun delete(alias: String) { pairs.remove(alias) }
    }
}
