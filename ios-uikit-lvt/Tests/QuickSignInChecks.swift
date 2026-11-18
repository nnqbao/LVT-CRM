import Foundation

/// Offline checks for đăng nhập nhanh (3.1.0): base64url, the exact device-key messages, the Keychain record's
/// account binding, Face ID / Touch ID labels and the WebAuthn JSON built for passkeys (simplewebauthn 9 shapes).
/// No Secure Enclave, network or credentials: pure Foundation fixtures.
@main
struct QuickSignInChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func json(_ text: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
        }

        // base64url.
        let bytes = Data([0xfb, 0xff, 0xfe, 0x00, 0x10])
        check(Base64URL.encode(bytes) == "-__-ABA", "base64url alphabet, no padding")
        check(Base64URL.decode("-__-ABA") == bytes && Base64URL.decode("+//+ABA=") == bytes, "Decode url-safe and standard")
        check(Base64URL.decode("abc$") == nil && Base64URL.decode("a") == nil, "Invalid input")
        for length in 0...40 {
            let sample = Data((0..<length).map { UInt8(($0 * 37 + 11) % 256) })
            check(Base64URL.decode(Base64URL.encode(sample)) == sample, "Round trip \(length)")
        }

        // Exact signed messages (convex/deviceAuthPolicy.ts deviceSignedMessage).
        check(String(decoding: DeviceKeyMessage.login(challengeId: "c1", challenge: "AbC_-"), as: UTF8.self) == "lvt-crm:device_login:c1:AbC_-", "Login message")
        check(String(decoding: DeviceKeyMessage.register(challengeId: "c2", challenge: "xyz"), as: UTF8.self) == "lvt-crm:device_register:c2:xyz", "Register message")

        // The switch is on only for the account that enabled it here; no password field exists.
        let record = DeviceCredentialRecord(credentialId: "cred", userId: "u1", email: "Lan@LVT.edu.vn", name: "Cô Lan", keyTag: "tag")
        check(record.belongs(toUserId: "u1", email: "other@x") && !record.belongs(toUserId: "u2", email: "lan@lvt.edu.vn"), "Bound to user id")
        check(DeviceCredentialRecord(credentialId: "c", userId: "", email: "Lan@LVT.edu.vn", name: "", keyTag: "t").belongs(toUserId: "", email: "lan@lvt.edu.vn"), "Email fallback")
        let encoded = String(decoding: (try? JSONEncoder().encode(record)) ?? Data(), as: UTF8.self)
        check(!encoded.lowercased().contains("password") && (try? JSONDecoder().decode(DeviceCredentialRecord.self, from: Data(encoded.utf8))) == record, "Record round trip, no password")

        // Labels by LAContext.biometryType.
        check(BiometryKind.faceID.switchTitle == "Đăng nhập bằng Face ID" && BiometryKind.touchID.switchTitle == "Đăng nhập bằng Touch ID", "Switch titles")
        check(BiometryKind.faceID.loginTitle(email: "lan@lvt.edu.vn") == "Đăng nhập bằng Face ID · lan@lvt.edu.vn", "Login button names the saved account")
        check(BiometryKind.none.label == "Face ID / Touch ID" && BiometryKind.touchID.symbol == "touchid", "Fallback label and symbol")
        check(QuickSignInError.cancelled.message == nil, "Cancellation is silent")
        check(QuickSignInError.credentialInvalid.message == "Vân tay / Face ID hoặc passkey trên máy này không còn hiệu lực. Đăng nhập bằng mật khẩu rồi bật lại.", "Invalid credential wording")

        // PublicKeyCredentialCreationOptionsJSON (simplewebauthn 9: user.id is the raw user id string).
        let challenge = Data((0..<32).map { UInt8($0) })
        let creation = """
        {"challenge":"\(Base64URL.encode(challenge))","rp":{"name":"CRM Lê Văn Tám","id":"lvt.vscgroup.io.vn"},
         "user":{"id":"k17abcdefghijklmnopq","name":"lan@lvt.edu.vn","displayName":"Cô Lan"},
         "pubKeyCredParams":[{"alg":-7,"type":"public-key"}],"timeout":120000,"attestation":"none",
         "excludeCredentials":[{"id":"\(Base64URL.encode(Data([1, 2, 3])))","type":"public-key"}],
         "authenticatorSelection":{"residentKey":"required","requireResidentKey":true,"userVerification":"required"}}
        """
        do {
            let options = try WebAuthnJSON.creationOptions(creation)
            check(options.rpId == "lvt.vscgroup.io.vn" && options.challenge == challenge, "rp.id and challenge")
            check(options.userName == "lan@lvt.edu.vn" && options.userDisplayName == "Cô Lan", "User names")
            check(options.excludeCredentialIds == [Data([1, 2, 3])], "excludeCredentials")
            check(options.userId == Base64URL.decode("k17abcdefghijklmnopq"), "user.id decoded as base64url")
        } catch { check(false, "Creation options parse: \(error)") }
        check(WebAuthnJSON.userHandle("abcde") == Data("abcde".utf8), "user.id that is not base64url falls back to UTF-8")
        check((try? WebAuthnJSON.creationOptions("{\"user\":{\"id\":\"x\"}}")) == nil, "Missing challenge rejected")
        check((try? WebAuthnJSON.creationOptions("not json")) == nil, "Invalid JSON rejected")

        // PublicKeyCredentialRequestOptionsJSON (no allowCredentials).
        do {
            let request = try WebAuthnJSON.requestOptions("{\"challenge\":\"\(Base64URL.encode(challenge))\",\"timeout\":120000,\"rpId\":\"lvt.vscgroup.io.vn\",\"userVerification\":\"required\"}")
            check(request.rpId == "lvt.vscgroup.io.vn" && request.challenge == challenge, "Request options")
            check(try WebAuthnJSON.requestOptions("{\"challenge\":\"AAAA\"}").rpId == WebAuthnJSON.defaultRpId, "Default RP id")
        } catch { check(false, "Request options parse: \(error)") }

        // RegistrationResponseJSON / AuthenticationResponseJSON.
        let credentialId = Data([9, 8, 7, 250])
        if let text = try? WebAuthnJSON.registrationResponse(credentialId: credentialId, clientDataJSON: Data("{}".utf8), attestationObject: Data([0xa3])) {
            let value = json(text)
            let response = value["response"] as? [String: Any] ?? [:]
            check(value["id"] as? String == Base64URL.encode(credentialId) && value["rawId"] as? String == value["id"] as? String, "id = rawId (base64url)")
            check(value["type"] as? String == "public-key" && value["authenticatorAttachment"] as? String == "platform", "Type and attachment")
            check(response["clientDataJSON"] as? String == "e30" && response["attestationObject"] as? String == "ow", "Raw fields base64url")
            check(response["transports"] as? [String] == ["internal", "hybrid"] && (value["clientExtensionResults"] as? [String: Any])?.isEmpty == true, "Transports and extensions")
        } else { check(false, "Registration JSON") }
        if let text = try? WebAuthnJSON.authenticationResponse(credentialId: credentialId, clientDataJSON: Data("{}".utf8), authenticatorData: Data([1]), signature: Data([2]), userHandle: Data("u".utf8)) {
            let response = json(text)["response"] as? [String: Any] ?? [:]
            check(response["authenticatorData"] as? String == "AQ" && response["signature"] as? String == "Ag" && response["userHandle"] as? String == "dQ", "Assertion fields")
            check(json(text)["id"] as? String == Base64URL.encode(credentialId), "Assertion id is the credential id")
        } else { check(false, "Authentication JSON") }
        if let text = try? WebAuthnJSON.authenticationResponse(credentialId: credentialId, clientDataJSON: Data(), authenticatorData: Data(), signature: Data(), userHandle: nil) {
            check((json(text)["response"] as? [String: Any])?["userHandle"] == nil, "No userHandle when absent")
        } else { check(false, "Authentication JSON without user handle") }

        print("QuickSignInChecks: \(checks) checks passed")
    }
}
