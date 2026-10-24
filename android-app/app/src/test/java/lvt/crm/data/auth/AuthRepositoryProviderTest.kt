package lvt.crm.data.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.convex.AuthApi
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Device-key / passkey sign-in reuses the password sign-in steps (tokens → session → gate → device session). */
@OptIn(ExperimentalCoroutinesApi::class)
class AuthRepositoryProviderTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun deviceKeySignInSavesTokensPublishesAndRegistersTheDevice() = runTest(dispatcher) {
        val store = InMemoryCredentialStore()
        val api = RecordingApi(mustChangePassword = false)
        var deviceSessions = 0
        val repository = AuthRepository(store, api, afterAuthenticated = { deviceSessions++; Result.success(Unit) })
        runCurrent()

        val params = JSONObject().put("credentialId", "cred").put("challengeId", "ch").put("signature", "sig")
        val result = repository.signInWithProvider("device-key", params)

        assertTrue(result.isSuccess)
        val (path, args) = api.actions.single()
        assertEquals("auth:signIn", path)
        assertEquals("device-key", args.getString("provider"))
        assertEquals("cred", args.getJSONObject("params").getString("credentialId"))
        assertEquals("issued-access", store.accessToken)
        assertTrue(repository.state.value is AuthState.SignedIn)
        assertEquals(1, deviceSessions)
    }

    @Test
    fun passkeySignInStillHitsTheMustChangePasswordGate() = runTest(dispatcher) {
        val store = InMemoryCredentialStore()
        val repository = AuthRepository(store, RecordingApi(mustChangePassword = true))
        runCurrent()

        val result = repository.signInWithProvider("passkey", JSONObject().put("challengeId", "c").put("response", "{}"))

        assertTrue(result.isSuccess)
        assertTrue(repository.state.value is AuthState.MustChangePassword)
    }

    @Test
    fun unknownProvidersAreRejectedWithoutCallingTheServer() = runTest(dispatcher) {
        val api = RecordingApi(mustChangePassword = false)
        val repository = AuthRepository(InMemoryCredentialStore(), api)
        runCurrent()
        assertTrue(repository.signInWithProvider("password", JSONObject()).isFailure)
        assertTrue(api.actions.isEmpty())
    }

    private class RecordingApi(private val mustChangePassword: Boolean) : AuthApi {
        val actions = mutableListOf<Pair<String, JSONObject>>()

        override suspend fun query(path: String, args: JSONObject, authenticated: Boolean): JSONObject =
            JSONObject().put(
                "user",
                JSONObject()
                    .put("_id", "u1")
                    .put("email", "gv@lvt.vn")
                    .put("name", "Cô A")
                    .put("role", "user")
                    .put("status", "active")
                    .put("mustChangePassword", mustChangePassword),
            )

        override suspend fun action(path: String, args: JSONObject, authenticated: Boolean): JSONObject {
            actions += path to args
            return JSONObject().put("tokens", JSONObject().put("token", "issued-access").put("refreshToken", "issued-refresh"))
        }

        override suspend fun actionWithToken(path: String, args: JSONObject, accessToken: String): JSONObject = JSONObject()
    }
}
