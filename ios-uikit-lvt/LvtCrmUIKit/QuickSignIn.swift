import Foundation

// Đăng nhập nhanh: Face ID / Touch ID (device key) and passkey. Pure Foundation helpers shared by the
// Secure Enclave / AuthenticationServices code (QuickSignInService.swift) and Tests/QuickSignInChecks.swift.
// Only public keys and signatures leave the device; no password is ever stored.

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Accepts base64url or standard base64, padded or not. nil for anything else.
    static func decode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard value.range(of: #"^[A-Za-z0-9+/]*={0,2}$"#, options: .regularExpression) != nil else { return nil }
        value = value.replacingOccurrences(of: "=", with: "")
        guard value.count % 4 != 1 else { return nil }
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }
}

/// Exact UTF-8 text the device key signs (convex/deviceAuthPolicy.ts `deviceSignedMessage`).
enum DeviceKeyMessage {
    static func login(challengeId: String, challenge: String) -> Data {
        Data("lvt-crm:device_login:\(challengeId):\(challenge)".utf8)
    }

    static func register(challengeId: String, challenge: String) -> Data {
        Data("lvt-crm:device_register:\(challengeId):\(challenge)".utf8)
    }
}

/// What this device remembers about its Face ID / Touch ID sign-in: never a password.
struct DeviceCredentialRecord: Codable, Equatable, Sendable {
    let credentialId: String
    let userId: String
    let email: String
    let name: String
    /// Keychain application tag of the Secure Enclave private key.
    let keyTag: String

    /// The Profile switch is on only for the account that enabled it on this device.
    func belongs(toUserId userId: String, email: String) -> Bool {
        if !self.userId.isEmpty, !userId.isEmpty { return self.userId == userId }
        return !email.isEmpty && self.email.caseInsensitiveCompare(email) == .orderedSame
    }
}

enum BiometryKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    case none

    var label: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Face ID / Touch ID"
        }
    }

    var symbol: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "faceid"
        }
    }

    var switchTitle: String { "Đăng nhập bằng \(label)" }

    /// Login button: "Đăng nhập bằng Face ID · lan@lvt.edu.vn".
    func loginTitle(email: String) -> String {
        email.isEmpty ? switchTitle : "\(switchTitle) · \(email)"
    }
}

enum QuickSignInError: Error, Equatable {
    /// User dismissed the system sheet / biometric prompt: no message.
    case cancelled
    /// Local key or credential missing or invalidated (e.g. a new face / fingerprint was enrolled).
    case credentialInvalid
    case unavailable(String)
    case failed(String)

    var message: String? {
        switch self {
        case .cancelled: return nil
        case .credentialInvalid: return ConvexHttpClient.teachingAuthMessage("DEVICE_CREDENTIAL_INVALID")
        case .unavailable(let text), .failed(let text): return text
        }
    }
}

// MARK: - WebAuthn JSON (PublicKeyCredential*OptionsJSON ⇄ native)

struct PasskeyCreationOptions: Equatable, Sendable {
    let rpId: String
    let challenge: Data
    let userId: Data
    let userName: String
    let userDisplayName: String
    let excludeCredentialIds: [Data]
}

struct PasskeyRequestOptions: Equatable, Sendable {
    let rpId: String
    let challenge: Data
}

enum WebAuthnJSON {
    static let defaultRpId = "lvt.vscgroup.io.vn"

    private static func object(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvexException(code: "PASSKEY_VERIFICATION_FAILED")
        }
        return object
    }

    /// simplewebauthn 9 puts the raw user id string in `user.id`; decode it as base64url like browsers / Android
    /// do, and fall back to its UTF-8 bytes when it is not valid base64url.
    static func userHandle(_ value: String) -> Data {
        if let data = Base64URL.decode(value), !data.isEmpty { return data }
        return Data(value.utf8)
    }

    static func creationOptions(_ json: String) throws -> PasskeyCreationOptions {
        let root = try object(json)
        guard let challengeText = root["challenge"] as? String, let challenge = Base64URL.decode(challengeText), !challenge.isEmpty,
              let user = root["user"] as? [String: Any], let userId = user["id"] as? String, !userId.isEmpty else {
            throw ConvexException(code: "PASSKEY_VERIFICATION_FAILED")
        }
        let rp = root["rp"] as? [String: Any]
        let rpId = (rp?["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultRpId
        let name = user["name"] as? String ?? ""
        return PasskeyCreationOptions(
            rpId: rpId,
            challenge: challenge,
            userId: userHandle(userId),
            userName: name,
            userDisplayName: user["displayName"] as? String ?? name,
            excludeCredentialIds: (root["excludeCredentials"] as? [[String: Any]] ?? []).compactMap {
                ($0["id"] as? String).flatMap(Base64URL.decode)
            }
        )
    }

    static func requestOptions(_ json: String) throws -> PasskeyRequestOptions {
        let root = try object(json)
        guard let challengeText = root["challenge"] as? String, let challenge = Base64URL.decode(challengeText), !challenge.isEmpty else {
            throw ConvexException(code: "PASSKEY_VERIFICATION_FAILED")
        }
        let rpId = (root["rpId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultRpId
        return PasskeyRequestOptions(rpId: rpId, challenge: challenge)
    }

    private static func string(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// RegistrationResponseJSON for `deviceAuth:registerPasskey`.
    static func registrationResponse(credentialId: Data, clientDataJSON: Data, attestationObject: Data) throws -> String {
        let id = Base64URL.encode(credentialId)
        return try string([
            "id": id,
            "rawId": id,
            "type": "public-key",
            "authenticatorAttachment": "platform",
            "response": [
                "clientDataJSON": Base64URL.encode(clientDataJSON),
                "attestationObject": Base64URL.encode(attestationObject),
                "transports": ["internal", "hybrid"],
            ] as [String: Any],
            "clientExtensionResults": [String: Any](),
        ])
    }

    /// AuthenticationResponseJSON for `auth:signIn` provider "passkey".
    static func authenticationResponse(
        credentialId: Data,
        clientDataJSON: Data,
        authenticatorData: Data,
        signature: Data,
        userHandle: Data?
    ) throws -> String {
        let id = Base64URL.encode(credentialId)
        var response: [String: Any] = [
            "clientDataJSON": Base64URL.encode(clientDataJSON),
            "authenticatorData": Base64URL.encode(authenticatorData),
            "signature": Base64URL.encode(signature),
        ]
        if let userHandle, !userHandle.isEmpty { response["userHandle"] = Base64URL.encode(userHandle) }
        return try string([
            "id": id,
            "rawId": id,
            "type": "public-key",
            "authenticatorAttachment": "platform",
            "response": response,
            "clientExtensionResults": [String: Any](),
        ])
    }
}
