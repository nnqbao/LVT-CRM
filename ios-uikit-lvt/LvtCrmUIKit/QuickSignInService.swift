import AuthenticationServices
import CryptoKit
import LocalAuthentication
import Security
import UIKit

/// Keychain record of this device's Face ID / Touch ID credential (credentialId + account). Never a password.
final class DeviceCredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private let service = "vn.lvt.crm.quick-sign-in"
    private let account = "device-credential"

    func load() -> DeviceCredentialRecord? {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceCredentialRecord.self, from: data)
    }

    @discardableResult
    func save(_ record: DeviceCredentialRecord) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(record) else { return false }
        deleteLocked()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        deleteLocked()
    }

    private func deleteLocked() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// P-256 key in the Secure Enclave, usable only after Face ID / Touch ID of the currently enrolled biometrics.
enum SecureEnclaveDeviceKey {
    static let tagPrefix = "vn.lvt.crm.uikit.device-key."

    struct Availability: Equatable {
        let kind: BiometryKind
        /// nil when the switch can be turned on.
        let unavailableReason: String?
    }

    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind: BiometryKind
        switch context.biometryType {
        case .faceID: kind = .faceID
        case .touchID: kind = .touchID
        case .opticID: kind = .opticID
        default: kind = .none
        }
        guard SecureEnclave.isAvailable else {
            return Availability(kind: kind, unavailableReason: "Thiết bị này không có Secure Enclave (ví dụ trình mô phỏng) nên không bật được.")
        }
        guard canEvaluate else {
            let reason: String
            switch (error as? LAError)?.code {
            case .biometryNotEnrolled?: reason = "Chưa thiết lập \(kind.label) trong Cài đặt của máy."
            case .passcodeNotSet?: reason = "Cần đặt mật mã cho máy trước khi bật \(kind.label)."
            case .biometryLockout?: reason = "\(kind.label) đang bị khóa. Mở khóa máy bằng mật mã rồi thử lại."
            default: reason = "Thiết bị này không hỗ trợ Face ID / Touch ID."
            }
            return Availability(kind: kind, unavailableReason: reason)
        }
        return Availability(kind: kind, unavailableReason: nil)
    }

    static func create(tag: String) throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else { throw QuickSignInError.failed("Không tạo được khóa thiết bị.") }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
                kSecAttrAccessControl as String: access,
            ] as [String: Any],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw QuickSignInError.failed("Không tạo được khóa thiết bị.")
        }
        return key
    }

    /// Raw X9.63 point (0x04 || X || Y, 65 bytes), base64 — the server wraps it as SPKI.
    static func publicKeyBase64(_ privateKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?, data.count == 65 else {
            throw QuickSignInError.failed("Không đọc được khóa công khai của thiết bị.")
        }
        return data.base64EncodedString()
    }

    /// The private key bound to an already-authenticated LAContext, so signing does not prompt again.
    static func load(tag: String, context: LAContext) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else { return nil }
        return (item as! SecKey)
    }

    /// ECDSA P-256 / SHA-256, DER signature, base64.
    static func sign(_ message: Data, with key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, &error) as Data? else {
            throw QuickSignInError.credentialInvalid
        }
        return signature.base64EncodedString()
    }

    static func delete(tag: String) {
        guard !tag.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Face ID / Touch ID (device key) and passkey: registration while signed in, and sign-in from the login screen.
/// Every sign-in goes through `AuthRepository`, so tokens, sessionContext and the mustChangePassword gate are the
/// same as for a password sign-in.
@MainActor
final class QuickSignInService {
    private let convex: ConvexHttpClient
    private let authRepository: AuthRepository
    private let store: DeviceCredentialStore
    private let passkeys = PasskeyAuthenticator()

    init(convex: ConvexHttpClient, authRepository: AuthRepository, store: DeviceCredentialStore = DeviceCredentialStore()) {
        self.convex = convex
        self.authRepository = authRepository
        self.store = store
    }

    var deviceRecord: DeviceCredentialRecord? { store.load() }
    var availability: SecureEnclaveDeviceKey.Availability { SecureEnclaveDeviceKey.availability() }

    func isDeviceKeyEnabled(for session: UserSession) -> Bool {
        deviceRecord?.belongs(toUserId: session.userId, email: session.email) == true
    }

    private var deviceName: String {
        let device = UIDevice.current
        return "\(device.name) · \(device.systemName) \(device.systemVersion)"
    }

    // MARK: Face ID / Touch ID

    private func authenticate(reason: String, kind: BiometryKind) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Hủy"
        context.localizedFallbackTitle = ""
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            guard ok else { throw QuickSignInError.cancelled }
            return context
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: throw QuickSignInError.cancelled
            case .biometryLockout:
                throw QuickSignInError.failed("\(kind.label) đang bị khóa do thử sai nhiều lần. Mở khóa máy bằng mật mã rồi thử lại.")
            case .biometryNotEnrolled, .biometryNotAvailable, .passcodeNotSet:
                throw QuickSignInError.unavailable(SecureEnclaveDeviceKey.availability().unavailableReason ?? "Thiết bị này không hỗ trợ Face ID / Touch ID.")
            default:
                throw QuickSignInError.failed("Không xác thực được \(kind.label). Thử lại.")
            }
        }
    }

    /// Profile switch on: new Secure Enclave key → signed registration challenge → credentialId in Keychain.
    func enableDeviceKey(for session: UserSession) async throws {
        let availability = self.availability
        if let reason = availability.unavailableReason { throw QuickSignInError.unavailable(reason) }
        let previous = store.load()
        let context = try await authenticate(reason: "Bật \(availability.kind.switchTitle.lowercasedFirst) cho \(session.email)", kind: availability.kind)
        let tag = SecureEnclaveDeviceKey.tagPrefix + UUID().uuidString
        do {
            let created = try SecureEnclaveDeviceKey.create(tag: tag)
            let publicKey = try SecureEnclaveDeviceKey.publicKeyBase64(created)
            let challenge = try await convex.mutation("deviceAuth:deviceRegisterChallenge")
            guard let challengeId = challenge["challengeId"] as? String, let value = challenge["challenge"] as? String else {
                throw ConvexException(code: "CHALLENGE_INVALID")
            }
            guard let key = SecureEnclaveDeviceKey.load(tag: tag, context: context) else { throw QuickSignInError.credentialInvalid }
            let signature = try SecureEnclaveDeviceKey.sign(DeviceKeyMessage.register(challengeId: challengeId, challenge: value), with: key)
            var args: [String: Any] = [
                "challengeId": challengeId,
                "publicKey": publicKey,
                "signature": signature,
                "deviceName": deviceName,
                "platform": "ios",
            ]
            if let previous, previous.belongs(toUserId: session.userId, email: session.email) {
                args["replaceCredentialId"] = previous.credentialId
            }
            let result = try await convex.action("deviceAuth:registerDeviceKey", args: args)
            guard let credentialId = result["credentialId"] as? String, !credentialId.isEmpty else {
                throw ConvexException(code: "DEVICE_CREDENTIAL_INVALID")
            }
            let record = DeviceCredentialRecord(credentialId: credentialId, userId: session.userId, email: session.email, name: session.name, keyTag: tag)
            guard store.save(record) else { throw QuickSignInError.failed("Không lưu được thông tin đăng nhập nhanh trên máy.") }
            if let previous, previous.keyTag != tag { SecureEnclaveDeviceKey.delete(tag: previous.keyTag) }
        } catch {
            SecureEnclaveDeviceKey.delete(tag: tag)
            throw error
        }
    }

    /// Profile switch off: forget the local key, then revoke it on the server (best-effort).
    func disableDeviceKey(for session: UserSession) async {
        guard let record = store.load() else { return }
        store.clear()
        SecureEnclaveDeviceKey.delete(tag: record.keyTag)
        guard record.belongs(toUserId: session.userId, email: session.email) else { return }
        _ = try? await convex.mutation("deviceAuth:removeMine", args: ["credentialId": record.credentialId])
    }

    private func forget(_ record: DeviceCredentialRecord) {
        if store.load()?.credentialId == record.credentialId { store.clear() }
        SecureEnclaveDeviceKey.delete(tag: record.keyTag)
    }

    func signInWithDeviceKey() async -> Result<UserSession, Error> {
        guard let record = store.load() else { return .failure(QuickSignInError.credentialInvalid) }
        let kind = availability.kind
        do {
            let challenge = try await convex.mutation("deviceAuth:deviceLoginChallenge", authenticated: false)
            guard let challengeId = challenge["challengeId"] as? String, let value = challenge["challenge"] as? String else {
                throw ConvexException(code: "CHALLENGE_INVALID")
            }
            let context = try await authenticate(reason: "Đăng nhập LVT CRM bằng \(kind.label)", kind: kind)
            // A new face / fingerprint invalidates a .biometryCurrentSet key: the key is gone or cannot sign.
            guard let key = SecureEnclaveDeviceKey.load(tag: record.keyTag, context: context),
                  let signature = try? SecureEnclaveDeviceKey.sign(DeviceKeyMessage.login(challengeId: challengeId, challenge: value), with: key) else {
                forget(record)
                return .failure(QuickSignInError.credentialInvalid)
            }
            let result = await authRepository.signIn(deviceCredentialId: record.credentialId, challengeId: challengeId, signature: signature)
            if case .failure(let error) = result, (error as? ConvexException)?.code == "DEVICE_CREDENTIAL_INVALID" {
                forget(record)
            }
            return result
        } catch {
            return .failure(error)
        }
    }

    // MARK: Passkey

    func createPasskey(anchor: ASPresentationAnchor) async throws {
        let value = try await convex.action("deviceAuth:passkeyRegistrationOptions")
        guard let challengeId = value["challengeId"] as? String, let options = value["options"] as? String else {
            throw ConvexException(code: "CHALLENGE_INVALID")
        }
        let response = try await passkeys.register(try WebAuthnJSON.creationOptions(options), anchor: anchor)
        _ = try await convex.action(
            "deviceAuth:registerPasskey",
            args: ["challengeId": challengeId, "response": response, "deviceName": deviceName, "platform": "ios"]
        )
    }

    func signInWithPasskey(anchor: ASPresentationAnchor) async -> Result<UserSession, Error> {
        do {
            let value = try await convex.action("deviceAuth:passkeyLoginOptions", authenticated: false)
            guard let challengeId = value["challengeId"] as? String, let options = value["options"] as? String else {
                throw ConvexException(code: "CHALLENGE_INVALID")
            }
            let response = try await passkeys.assert(try WebAuthnJSON.requestOptions(options), anchor: anchor)
            return await authRepository.signIn(passkeyChallengeId: challengeId, response: response)
        } catch {
            return .failure(error)
        }
    }

    /// Message for an error banner; nil when the user cancelled (silent).
    static func message(for error: Error) -> String? {
        if let error = error as? QuickSignInError { return error.message }
        if let error = error as? ConvexException {
            let text = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.range(of: #"^\[Request ID:[^\]]+\]\s*Server Error\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
                || text.caseInsensitiveCompare("Server Error") == .orderedSame {
                return "Không đăng nhập được. Thử lại hoặc đăng nhập bằng mật khẩu."
            }
            return ConvexHttpClient.humanize(error.message)
        }
        if (error as NSError).domain == NSURLErrorDomain { return "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại." }
        return ConvexHttpClient.humanize(error.localizedDescription)
    }
}

/// ASAuthorizationController wrapper (platform passkeys only). Cancellation maps to `QuickSignInError.cancelled`.
@MainActor
final class PasskeyAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?
    private weak var anchor: ASPresentationAnchor?

    func register(_ options: PasskeyCreationOptions, anchor: ASPresentationAnchor) async throws -> String {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
        let request = provider.createCredentialRegistrationRequest(
            challenge: options.challenge,
            name: options.userName,
            userID: options.userId
        )
        request.displayName = options.userDisplayName
        request.userVerificationPreference = .required
        request.excludedCredentials = options.excludeCredentialIds.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        let authorization = try await perform(request, anchor: anchor)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = credential.rawAttestationObject else {
            throw QuickSignInError.failed("Không tạo được passkey. Thử lại.")
        }
        return try WebAuthnJSON.registrationResponse(
            credentialId: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            attestationObject: attestation
        )
    }

    func assert(_ options: PasskeyRequestOptions, anchor: ASPresentationAnchor) async throws -> String {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.userVerificationPreference = .required
        let authorization = try await perform(request, anchor: anchor)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw QuickSignInError.failed("Không dùng được passkey này. Thử lại.")
        }
        return try WebAuthnJSON.authenticationResponse(
            credentialId: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData,
            signature: credential.signature,
            userHandle: credential.userID
        )
    }

    private func perform(_ request: ASAuthorizationRequest, anchor: ASPresentationAnchor) async throws -> ASAuthorization {
        guard continuation == nil else { throw QuickSignInError.cancelled }
        self.anchor = anchor
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }

    private static func map(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain, let code = ASAuthorizationError.Code(rawValue: nsError.code) else {
            return QuickSignInError.failed("Không dùng được passkey lúc này. Thử lại.")
        }
        switch code {
        case .canceled:
            return QuickSignInError.cancelled
        case .matchedExcludedCredential:
            return QuickSignInError.failed("Máy này đã có passkey cho tài khoản của bạn.")
        default:
            let detail = "\(nsError.localizedDescription) \(nsError.userInfo)".lowercased()
            if detail.contains("associated") || detail.contains("webcredentials") {
                return QuickSignInError.failed("Ứng dụng chưa được liên kết với lvt.vscgroup.io.vn nên chưa dùng được passkey.")
            }
            return QuickSignInError.failed("Không dùng được passkey lúc này. Thử lại.")
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(Self.map(error))) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor { return anchor }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.lazy.compactMap(\.keyWindow).first { return window }
            return ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
