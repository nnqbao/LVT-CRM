package lvt.crm.data.auth

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.convex.AuthApi
import lvt.crm.data.convex.ConvexException
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthRepositoryRaceTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun signOutWhileSignInIsInFlightPreventsCredentialWrite() = runTest(dispatcher) {
        val store = InMemoryCredentialStore()
        val signInStarted = CompletableDeferred<Unit>()
        val releaseSignIn = CompletableDeferred<Unit>()
        val api = FakeAuthApi(
            signInResponse = {
                signInStarted.complete(Unit)
                releaseSignIn.await()
                tokenResponse("issued-access", "issued-refresh")
            },
        )
        val repository = AuthRepository(store, api)
        runCurrent()

        val result = async { repository.signIn("user@example.com", "password") }
        signInStarted.await()
        repository.signOut()
        releaseSignIn.complete(Unit)

        assertTrue(result.await().isFailure)
        assertNull(store.accessToken)
        assertNull(store.refreshToken)
        assertEquals(AuthState.SignedOut, repository.state.value)
    }

    @Test
    fun transientSessionFailureRetainsNewlyIssuedCredentials() = runTest(dispatcher) {
        val store = InMemoryCredentialStore()
        val api = FakeAuthApi(
            signInResponse = { tokenResponse("issued-access", "issued-refresh") },
            sessionResponse = { throw ConvexException("HTTP_503", "temporary") },
        )
        val repository = AuthRepository(store, api)
        runCurrent()

        val result = repository.signIn("user@example.com", "password")

        assertTrue(result.isFailure)
        assertEquals("issued-access", store.accessToken)
        assertEquals("issued-refresh", store.refreshToken)
    }

    @Test
    fun accountSwitchSessionFailureRestoresPreviousIdentityAndCredentials() = runTest(dispatcher) {
        val store = InMemoryCredentialStore("account-a-access", "account-a-refresh")
        var sessionRequest = 0
        val switchedSessionStarted = CompletableDeferred<Unit>()
        val releaseSwitchedSession = CompletableDeferred<Unit>()
        val api = FakeAuthApi(
            signInResponse = { tokenResponse("account-b-access", "account-b-refresh") },
            sessionResponse = {
                if (++sessionRequest == 1) {
                    sessionResponse("account-a-id", "account-a@example.com")
                } else {
                    switchedSessionStarted.complete(Unit)
                    releaseSwitchedSession.await()
                    throw ConvexException("HTTP_503", "temporary")
                }
            },
        )
        val repository = AuthRepository(store, api)
        runCurrent()

        val result = async { repository.signIn("account-b@example.com", "password") }
        switchedSessionStarted.await()

        assertEquals(AuthState.Loading, repository.state.value)
        assertEquals("account-b-access", store.accessToken)
        assertEquals("account-b-refresh", store.refreshToken)

        releaseSwitchedSession.complete(Unit)
        val completedResult = result.await()

        assertTrue(completedResult.isFailure)
        assertEquals("account-a-access", store.accessToken)
        assertEquals("account-a-refresh", store.refreshToken)
        assertEquals("account-a-id", repository.state.value.signedInUserId())
    }

    @Test
    fun accountSwitchGenericFailureRestoresPreviousIdentityAndCredentials() = runTest(dispatcher) {
        val store = InMemoryCredentialStore("account-a-access", "account-a-refresh")
        var sessionRequest = 0
        val api = FakeAuthApi(
            signInResponse = { tokenResponse("account-b-access", "account-b-refresh") },
            sessionResponse = {
                if (++sessionRequest == 1) {
                    sessionResponse("account-a-id", "account-a@example.com")
                } else {
                    throw IllegalStateException("connection reset")
                }
            },
        )
        val repository = AuthRepository(store, api)
        runCurrent()

        val result = repository.signIn("account-b@example.com", "password")

        assertTrue(result.isFailure)
        assertEquals("SIGN_IN_FAILED", (result.exceptionOrNull() as ConvexException).code)
        assertEquals("account-a-access", store.accessToken)
        assertEquals("account-a-refresh", store.refreshToken)
        assertEquals("account-a-id", repository.state.value.signedInUserId())
    }

    @Test
    fun rejectedSessionClearsOnlyCredentialsIssuedByThatSignIn() = runTest(dispatcher) {
        val store = InMemoryCredentialStore()
        val api = FakeAuthApi(
            signInResponse = { tokenResponse("issued-access", "issued-refresh") },
            sessionResponse = { throw ConvexException("UNAUTHENTICATED") },
        )
        val repository = AuthRepository(store, api)
        runCurrent()

        val result = repository.signIn("user@example.com", "password")

        assertTrue(result.isFailure)
        assertNull(store.accessToken)
        assertNull(store.refreshToken)
        assertEquals(AuthState.SignedOut, repository.state.value)
    }

    @Test
    fun authFailureInOneRestorePreventsAnotherRestoreFromPublishingSignedIn() = runTest(dispatcher) {
        val store = InMemoryCredentialStore("access", "refresh")
        val validRestoreStarted = CompletableDeferred<Unit>()
        val releaseValidRestore = CompletableDeferred<Unit>()
        var sessionRequest = 0
        val api = FakeAuthApi(
            signInResponse = { JSONObject() },
            sessionResponse = {
                when (++sessionRequest) {
                    1 -> {
                        validRestoreStarted.complete(Unit)
                        releaseValidRestore.await()
                        sessionResponse("user-id", "user@example.com")
                    }

                    2 -> throw ConvexException("UNAUTHENTICATED")
                    else -> error("Unexpected session request")
                }
            },
        )
        val repository = AuthRepository(store, api)
        runCurrent()
        validRestoreStarted.await()

        val failingRestore = async { repository.restoreSession() }
        runCurrent()
        failingRestore.await()

        releaseValidRestore.complete(Unit)
        advanceUntilIdle()

        assertNull(store.accessToken)
        assertNull(store.refreshToken)
        assertEquals(AuthState.SignedOut, repository.state.value)
    }

    @Test
    fun signOutClearsLocallyBeforeCleanupAndStillAttemptsRemoteRevocation() = runTest(dispatcher) {
        val store = InMemoryCredentialStore("access", "refresh")
        val api = FakeAuthApi(signInResponse = { JSONObject() })
        val repository = AuthRepository(
            store,
            api,
            beforeSignOut = { throw IllegalStateException("device cleanup failed") },
        )
        runCurrent()

        repository.signOut()

        assertNull(store.accessToken)
        assertNull(store.refreshToken)
        assertEquals(AuthState.SignedOut, repository.state.value)
        assertEquals(0, api.actionWithTokenCalls)

        runCurrent()
        assertEquals(1, api.actionWithTokenCalls)
    }

    private class FakeAuthApi(
        private val signInResponse: suspend () -> JSONObject,
        private val sessionResponse: suspend () -> JSONObject = { defaultSessionResponse() },
    ) : AuthApi {
        var actionWithTokenCalls = 0

        override suspend fun query(path: String, args: JSONObject, authenticated: Boolean): JSONObject =
            sessionResponse()

        override suspend fun action(path: String, args: JSONObject, authenticated: Boolean): JSONObject =
            signInResponse()

        override suspend fun actionWithToken(
            path: String,
            args: JSONObject,
            accessToken: String,
        ): JSONObject {
            actionWithTokenCalls++
            return JSONObject()
        }
    }

    companion object {
        private fun tokenResponse(access: String, refresh: String) = JSONObject().put(
            "tokens",
            JSONObject()
                .put("token", access)
                .put("refreshToken", refresh),
        )

        private fun defaultSessionResponse() = sessionResponse("user-id", "user@example.com")

        private fun sessionResponse(userId: String, email: String) = JSONObject()
            .put(
                "user",
                JSONObject()
                    .put("_id", userId)
                    .put("email", email)
                    .put("name", "User")
                    .put("role", "user")
                    .put("status", "active"),
            )

        private fun AuthState.signedInUserId(): String? = when (this) {
            is AuthState.SignedIn -> session.userId
            is AuthState.MustChangePassword -> session.userId
            AuthState.Loading,
            AuthState.SignedOut,
            -> null
        }
    }
}
