import XCTest
import CryptoKit
@testable import ApnsClient

final class ApnsJWTTests: XCTestCase {
    func testJWTHasThreeParts() throws {
        let key = P256.Signing.PrivateKey()
        let pem = key.pemRepresentation
        let jwt = try ApnsJWT(teamId: "TEAM12345A", keyId: "KEY1234567", p8Pem: pem)
        let token = try jwt.token()
        let parts = token.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
    }

    func testJWTSignatureRoundTripDecodes() throws {
        let key = P256.Signing.PrivateKey()
        let jwt = try ApnsJWT(teamId: "T", keyId: "K", p8Pem: key.pemRepresentation)
        let token = try jwt.token()
        let parts = token.split(separator: ".").map(String.init)
        let signing = "\(parts[0]).\(parts[1])"
        // Verify the signature using the public key + signing input.
        let sig = try base64URLDecode(parts[2])
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: sig)
        let valid = key.publicKey.isValidSignature(signature, for: Data(signing.utf8))
        XCTAssertTrue(valid)
    }

    private func base64URLDecode(_ s: String) throws -> Data {
        var s = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else {
            throw NSError(domain: "test", code: 0)
        }
        return data
    }
}
