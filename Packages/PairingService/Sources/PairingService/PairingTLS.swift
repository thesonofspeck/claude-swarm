import Foundation
import Security
import CryptoKit
import os

private let log = Logger(subsystem: "com.claudeswarm", category: "pairing.tls")

/// Provisions and persists a self-signed P-256 identity that the
/// PairingServer presents over TLS. On first run the cert + key are
/// generated via the system's `openssl` (LibreSSL on macOS); both PEMs
/// are stored in Keychain so the same identity survives reboots and
/// already-paired iPhones don't have to re-pair.
public enum PairingTLS {
    public struct Identity: Sendable {
        /// The SecIdentity (cert + private key) ready for NWProtocolTLS.
        public let secIdentity: SecIdentity
        /// SHA-256 of the cert DER, hex-encoded. Goes into the QR so iOS
        /// can pin it when it connects.
        public let thumbprintHex: String
    }

    public enum TLSError: Error, LocalizedError {
        case opensslNotFound
        case opensslFailed(String)
        case keychainFailed(OSStatus, String)
        case parseFailed(String)

        public var errorDescription: String? {
            switch self {
            case .opensslNotFound:
                return "openssl is not at /usr/bin/openssl. Pairing TLS can't be provisioned."
            case .opensslFailed(let m): return "openssl: \(m)"
            case .keychainFailed(let s, let m): return "Keychain (\(s)): \(m)"
            case .parseFailed(let m): return "TLS material decode: \(m)"
            }
        }
    }

    private static let service = "com.claudeswarm.pairings.tls"
    private static let certAccount = "cert.pem"
    private static let keyAccount = "key.pem"

    public static func loadOrGenerate(macId: String) throws -> Identity {
        if let pair = try? loadPersisted(),
           let identity = try? buildIdentity(certPEM: pair.certPEM, keyPEM: pair.keyPEM) {
            return identity
        }
        let pair = try generatePair(macId: macId)
        try persist(certPEM: pair.certPEM, keyPEM: pair.keyPEM)
        return try buildIdentity(certPEM: pair.certPEM, keyPEM: pair.keyPEM)
    }

    // MARK: - Generation

    private struct PEMPair { let certPEM: String; let keyPEM: String }

    private static func generatePair(macId: String) throws -> PEMPair {
        let opensslPath = "/usr/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: opensslPath) else {
            throw TLSError.opensslNotFound
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let keyURL = temp.appendingPathComponent("key.pem")
        let certURL = temp.appendingPathComponent("cert.pem")

        // P-256, 10-year self-signed; CN is the stable mac id so it's stable
        // across renewals. SAN includes the local hostname for log clarity.
        let subj = "/CN=\(macId)"
        try runOpenSSL(opensslPath, args: [
            "req", "-x509",
            "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:P-256",
            "-keyout", keyURL.path,
            "-out", certURL.path,
            "-days", "3650",
            "-nodes",
            "-subj", subj
        ])
        let certPEM = try String(contentsOf: certURL, encoding: .utf8)
        let keyPEM = try String(contentsOf: keyURL, encoding: .utf8)
        return PEMPair(certPEM: certPEM, keyPEM: keyPEM)
    }

    private static func runOpenSSL(_ executable: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = (try? err.fileHandleForReading.readToEnd()).flatMap {
                String(data: $0, encoding: .utf8)
            } ?? ""
            throw TLSError.opensslFailed("exit \(process.terminationStatus): \(stderr)")
        }
    }

    // MARK: - Persistence

    private static func persist(certPEM: String, keyPEM: String) throws {
        try keychainWrite(certPEM, account: certAccount)
        try keychainWrite(keyPEM, account: keyAccount)
    }

    private static func loadPersisted() throws -> PEMPair {
        PEMPair(
            certPEM: try keychainRead(account: certAccount),
            keyPEM: try keychainRead(account: keyAccount)
        )
    }

    private static func keychainWrite(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw TLSError.keychainFailed(status, "writing \(account)")
        }
    }

    private static func keychainRead(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw TLSError.keychainFailed(status, "reading \(account)")
        }
        return string
    }

    // MARK: - SecIdentity assembly

    private static func buildIdentity(certPEM: String, keyPEM: String) throws -> Identity {
        guard let certData = pemToDER(certPEM, header: "CERTIFICATE") else {
            throw TLSError.parseFailed("cert PEM had no CERTIFICATE block")
        }
        guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw TLSError.parseFailed("SecCertificateCreateWithData failed")
        }
        guard let keyData = pemToDER(keyPEM, header: "EC PRIVATE KEY") ?? pemToDER(keyPEM, header: "PRIVATE KEY") else {
            throw TLSError.parseFailed("key PEM had no EC PRIVATE KEY block")
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &error) else {
            let m = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw TLSError.parseFailed("SecKeyCreateWithData: \(m)")
        }

        let identity = try makeSecIdentity(cert: cert, key: secKey)
        let thumbprint = SHA256.hash(data: certData).map { String(format: "%02x", $0) }.joined()
        return Identity(secIdentity: identity, thumbprintHex: thumbprint)
    }

    /// SecIdentity has no public constructor that takes an in-memory key.
    /// Workaround: import the cert and a PKCS#12 of the key into a
    /// transient Keychain item, then SecItemCopyMatching the identity back
    /// out by label. Each call uses a fresh label so we don't collide.
    private static func makeSecIdentity(cert: SecCertificate, key: SecKey) throws -> SecIdentity {
        let label = "com.claudeswarm.pairings.tls.\(UUID().uuidString)"
        // Add cert
        let certAdd: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: label
        ]
        var status = SecItemAdd(certAdd as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw TLSError.keychainFailed(status, "import cert")
        }
        // Add key
        let keyAdd: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key,
            kSecAttrLabel as String: label
        ]
        status = SecItemAdd(keyAdd as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw TLSError.keychainFailed(status, "import key")
        }
        // Copy out identity
        let q: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true
        ]
        var out: CFTypeRef?
        status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let outRef = out, CFGetTypeID(outRef) == SecIdentityGetTypeID() else {
            throw TLSError.keychainFailed(status, "copy identity")
        }
        // We could clean up the labelled cert/key items here, but
        // SecIdentity holds its own refs so leaving them is safe and
        // avoids an extra round trip.
        return outRef as! SecIdentity
    }

    private static func pemToDER(_ pem: String, header: String) -> Data? {
        let begin = "-----BEGIN \(header)-----"
        let end = "-----END \(header)-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end),
              beginRange.upperBound <= endRange.lowerBound else { return nil }
        let body = pem[beginRange.upperBound..<endRange.lowerBound]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Data(base64Encoded: body)
    }
}
