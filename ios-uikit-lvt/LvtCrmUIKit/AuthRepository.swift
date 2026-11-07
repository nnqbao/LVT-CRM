import Combine
import Foundation

@MainActor
final class AuthRepository: ObservableObject {
    @Published private(set) var state: AuthState = .loading
    @Published private(set) var bootstrapError: String?

    private let tokenStore: CredentialStore
    private let convex: ConvexHttpClient
    private let beforeSignOut: ((String) async -> Void)?
    private var authGeneration: Int64 = 0

    init(
        tokenStore: CredentialStore,
        convex: ConvexHttpClient,
        beforeSignOut: ((String) async -> Void)? = nil
    ) {
        self.tokenStore = tokenStore
        self.convex = convex
        self.beforeSignOut = beforeSignOut
        Task { await restoreSession() }
    }

    func restoreSession() async {
        let generation = authGeneration
        let credentials = await readStoredCredentials()
        guard let credentials else {
            if authGeneration == generation { state = .signedOut }
            return
        }
        do {
            if let session = try await fetchSession(timeoutSeconds: 12) {
                _ = publish(session, generation: generation, expectedCredentials: credentials)
            } else {
                _ = clearCurrentCredentialsAndSignOut(credentials, generation: generation)
            }
        } catch let error as ConvexException where isAuthenticationFailure(error) {
            _ = clearCurrentCredentialsAndSignOut(credentials, generation: generation)
        } catch {
            // Network trouble: keep the saved sign-in; the app shows "Không có kết nối" and retries.
            // Any other failure keeps the former behaviour (sign-in screen with the reason, tokens kept).
            if authGeneration == generation, case .loading = state {
                if Self.isConnectivityFailure(error) {
                    state = .offline
                } else {
                    bootstrapError = (error as? ConvexException)?.message
                        ?? "Không kết nối được máy chủ. Kiểm tra mạng rồi đăng nhập lại."
                    state = .signedOut
                }
            }
        }
    }

    func failOpenIfStillLoading() {
        guard case .loading = state else { return }
        if tokenStore.snapshot() != nil {
            state = .offline
            return
        }
        if bootstrapError == nil {
            bootstrapError = "Không kết nối được máy chủ. Kiểm tra mạng rồi đăng nhập lại."
        }
        state = .signedOut
    }

    /// "Thử lại" on the Không có kết nối screen, or the network came back.
    func retryRestore() async {
        guard case .offline = state else { return }
        state = .loading
        await restoreSession()
    }

    func signIn(email: String, password: String) async -> Result<UserSession, Error> {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !password.isEmpty else {
            return .failure(ConvexException(code: "EMAIL_PASSWORD_REQUIRED", message: "Nhập email và mật khẩu."))
        }
        // App Review demo account → demo environment; any other account → the real backend.
        let wasDemo = DemoEnvironment.isActive
        DemoEnvironment.setActive(DemoEnvironment.isDemoAccount(normalized))
        let result = await signIn(
            provider: "password",
            params: ["email": normalized, "password": password, "flow": "signIn"]
        )
        if case .failure = result, !state.isAuthenticated { DemoEnvironment.setActive(wasDemo) }
        return result
    }

    /// Face ID / Touch ID: the Secure Enclave key signed a single-use `device_login` challenge.
    func signIn(deviceCredentialId: String, challengeId: String, signature: String) async -> Result<UserSession, Error> {
        await signIn(
            provider: "device-key",
            params: ["credentialId": deviceCredentialId, "challengeId": challengeId, "signature": signature]
        )
    }

    /// Passkey: AuthenticationResponseJSON for a `passkey_login` challenge.
    func signIn(passkeyChallengeId challengeId: String, response: String) async -> Result<UserSession, Error> {
        await signIn(provider: "passkey", params: ["challengeId": challengeId, "response": response])
    }

    /// Every sign-in method shares the same steps: tokens → Keychain, sessionContext, publish (so the
    /// mustChangePassword gate still applies), rollback of an interrupted account switch.
    private func signIn(provider: String, params: [String: Any]) async -> Result<UserSession, Error> {
        let previousCredentials = tokenStore.snapshot()
        let previousState = state
        authGeneration += 1
        let generation = authGeneration
        let credentialRevision = tokenStore.invalidatePendingWrites()
        if previousCredentials != nil, previousState.isAuthenticated { state = .loading }

        var credentialsIssued = false
        var issuedCredentials: CredentialSnapshot?
        do {
            let result = try await convex.action(
                "auth:signIn",
                args: ["provider": provider, "params": params],
                authenticated: false
            )
            guard let tokens = result["tokens"] as? [String: Any],
                  let access = tokens["token"] as? String,
                  let refresh = tokens["refreshToken"] as? String else {
                throw ConvexException(code: "NO_TOKENS", message: "Đăng nhập không trả về token.")
            }

            credentialsIssued = authGeneration == generation
                && tokenStore.saveIfRevision(credentialRevision, accessToken: access, refreshToken: refresh)
            guard credentialsIssued else { return .failure(ConvexException(code: "SIGN_IN_SUPERSEDED")) }
            issuedCredentials = CredentialSnapshot(
                accessToken: access,
                refreshToken: refresh,
                revision: credentialRevision
            )
            bootstrapError = nil
            guard let session = try await fetchSession(timeoutSeconds: 45) else {
                throw ConvexException(code: "NO_SESSION", message: "Không tải được phiên đăng nhập.")
            }
            guard publish(session, generation: generation) else {
                return .failure(ConvexException(code: "SIGN_IN_SUPERSEDED"))
            }
            return .success(session)
        } catch {
            if let previousCredentials, previousState.isAuthenticated {
                rollbackAccountSwitch(
                    generation: generation,
                    credentialRevision: credentialRevision,
                    issuedCredentials: issuedCredentials,
                    previousCredentials: previousCredentials,
                    previousState: previousState
                )
            } else if credentialsIssued, let issuedCredentials, invalidatesCredentials(error) {
                _ = clearCurrentCredentialsAndSignOut(issuedCredentials, generation: generation)
            }
            return .failure(error)
        }
    }

    func requestPasswordReset(email: String) async -> Result<Void, Error> {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return .failure(ConvexException(code: "EMAIL_REQUIRED", message: "Nhập email."))
        }
        do {
            _ = try await convex.action(
                "users:requestPasswordReset",
                args: ["email": normalized],
                authenticated: false
            )
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func changePassword(newPassword: String) async -> Result<Void, Error> {
        let generation = authGeneration
        guard newPassword.count >= 8 else {
            return .failure(ConvexException(code: "PASSWORD_TOO_SHORT"))
        }
        do {
            _ = try await convex.action("users:changeOwnPassword", args: ["newPassword": newPassword])
        } catch {
            return .failure(error)
        }
        do {
            if let session = try await fetchSession(timeoutSeconds: 45) {
                _ = publish(session, generation: generation)
            } else if authGeneration == generation {
                authGeneration += 1
                tokenStore.clear()
                state = .signedOut
            }
            return .success(())
        } catch {
            return .success(())
        }
    }

    func signOut() {
        authGeneration += 1
        let accessToken = tokenStore.accessToken
        tokenStore.clear()
        state = .signedOut
        guard let accessToken, !accessToken.isEmpty else { return }
        Task {
            if let beforeSignOut {
                await beforeSignOut(accessToken)
            }
            _ = try? await convex.actionWithToken("auth:signOut", args: [:], accessToken: accessToken)
        }
    }

    @discardableResult
    private func publish(
        _ session: UserSession,
        generation: Int64,
        expectedCredentials: CredentialSnapshot? = nil
    ) -> Bool {
        guard authGeneration == generation else { return false }
        if let expectedCredentials, tokenStore.snapshot() != expectedCredentials { return false }
        state = session.mustChangePassword ? .mustChangePassword(session) : .signedIn(session)
        return true
    }

    private func clearCurrentCredentialsAndSignOut(
        _ credentials: CredentialSnapshot,
        generation: Int64
    ) -> Bool {
        guard authGeneration == generation, tokenStore.clearIfCurrent(credentials) else { return false }
        authGeneration += 1
        state = .signedOut
        return true
    }

    private func readStoredCredentials() async -> CredentialSnapshot? {
        let store = tokenStore
        return await withTaskGroup(of: CredentialSnapshot?.self) { group in
            group.addTask {
                store.snapshot()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func fetchSession(timeoutSeconds: Double) async throws -> UserSession? {
        let client = convex
        return try await withThrowingTaskGroup(of: UserSession?.self) { group in
            group.addTask {
                let result = try await client.query("users:sessionContext")
                return UserSession(sessionContext: result)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw ConvexException(
                    code: "SESSION_TIMEOUT",
                    message: "Không kết nối được máy chủ. Thử mở lại ứng dụng."
                )
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    /// No network, the server unreachable or not answering: never a reason to sign out.
    static func isConnectivityFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let error = error as? ConvexException { return ["SESSION_TIMEOUT", "INVALID_JSON"].contains(error.code) }
        return (error as NSError).domain == NSURLErrorDomain
    }

    private func isAuthenticationFailure(_ error: ConvexException) -> Bool {
        error.code.localizedCaseInsensitiveContains("Unauthenticated")
            || error.code.localizedCaseInsensitiveContains("Authentication")
            || error.code == "UNAUTHENTICATED"
    }

    private func invalidatesCredentials(_ error: Error) -> Bool {
        guard let error = error as? ConvexException else { return false }
        return error.code == "NO_SESSION"
            || error.code.localizedCaseInsensitiveContains("Unauthenticated")
            || error.code.localizedCaseInsensitiveContains("Authentication")
            || error.code == "UNAUTHENTICATED"
    }

    private func rollbackAccountSwitch(
        generation: Int64,
        credentialRevision: Int64,
        issuedCredentials: CredentialSnapshot?,
        previousCredentials: CredentialSnapshot,
        previousState: AuthState
    ) {
        guard authGeneration == generation else { return }
        let restored: Bool
        if issuedCredentials == nil {
            restored = tokenStore.snapshot()?.hasSameTokens(as: previousCredentials) == true
        } else if let issuedCredentials {
            restored = tokenStore.replaceIfCurrent(
                issuedCredentials,
                accessToken: previousCredentials.accessToken,
                refreshToken: previousCredentials.refreshToken
            )
        } else {
            restored = false
        }
        if restored {
            state = previousState
        } else if tokenStore.clearIfRevision(credentialRevision) {
            authGeneration += 1
            state = .signedOut
        }
    }
}

private extension CredentialSnapshot {
    func hasSameTokens(as other: CredentialSnapshot) -> Bool {
        accessToken == other.accessToken && refreshToken == other.refreshToken
    }
}
