import Foundation
import CryptoKit

/// Builds the short-lived JWT APNs requires. JWTs are valid for 60 minutes
/// per Apple's documentation; we mint a fresh one every ~50 minutes.
public struct ApnsJWT {
    public let teamId: String
    public let keyId: String
    public let privateKey: P256.Signing.PrivateKey

    public init(teamId: String, keyId: String, p8Pem: String) throws {
        self.teamId = teamId
        self.keyId = keyId
        self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: p8Pem)
    }

    public func token(at now: Date = Date()) throws -> String {
        let header: [String: String] = ["alg": "ES256", "kid": keyId, "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": teamId,
            "iat": Int(now.timeIntervalSince1970)
        ]
        let headerB64 = try Self.base64URL(JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let claimsB64 = try Self.base64URL(JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        let signing = "\(headerB64).\(claimsB64)"
        let signature = try privateKey.signature(for: Data(signing.utf8))
        let signatureB64 = Self.base64URL(signature.rawRepresentation)
        return "\(signing).\(signatureB64)"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

actor JWTCache {
    private var current: (token: String, expires: Date)?
    public func get(_ build: () throws -> String) throws -> String {
        if let current, current.expires > Date().addingTimeInterval(60) {
            return current.token
        }
        let token = try build()
        current = (token, Date().addingTimeInterval(50 * 60))
        return token
    }
    public func invalidate() { current = nil }
}
