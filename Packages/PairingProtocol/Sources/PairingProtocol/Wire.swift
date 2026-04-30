import Foundation

/// Protocol version. Bump when changing the shape of any wire type so
/// mismatched Mac↔iOS builds fail loudly at handshake.
public let WireProtocolVersion = 1

// MARK: - Pairing handshake

/// Encoded into the QR shown by the Mac. iOS scans this to learn how to
/// reach the host and how to authenticate the pair-attempt.
public struct PairingInvite: Codable, Equatable, Sendable {
    public let host: String          // hostname or IP reachable on the user's VPN/LAN
    public let port: UInt16
    public let macId: String         // stable identifier for this Mac install
    public let macName: String
    public let pairingCode: String   // single-use code valid for ~5 minutes
    public let bundleId: String      // expected iOS bundle id (sanity check)
    /// SHA-256 of the Mac's TLS cert DER, hex-encoded. iOS pins on this so
    /// a man-in-the-middle on the LAN can't impersonate the server.
    public let certThumbprint: String
    public let protocolVersion: Int

    public init(
        host: String, port: UInt16,
        macId: String, macName: String,
        pairingCode: String, bundleId: String,
        certThumbprint: String,
        protocolVersion: Int = WireProtocolVersion
    ) {
        self.host = host
        self.port = port
        self.macId = macId
        self.macName = macName
        self.pairingCode = pairingCode
        self.bundleId = bundleId
        self.certThumbprint = certThumbprint
        self.protocolVersion = protocolVersion
    }

    /// Backwards-compatible decoder so older invites without a thumbprint
    /// still parse (they pin to "" which the iOS client refuses).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(UInt16.self, forKey: .port)
        macId = try c.decode(String.self, forKey: .macId)
        macName = try c.decode(String.self, forKey: .macName)
        pairingCode = try c.decode(String.self, forKey: .pairingCode)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        certThumbprint = (try? c.decode(String.self, forKey: .certThumbprint)) ?? ""
        protocolVersion = (try? c.decode(Int.self, forKey: .protocolVersion)) ?? WireProtocolVersion
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, macId, macName, pairingCode, bundleId, certThumbprint, protocolVersion
    }
}

/// First message iOS sends after connecting. The server matches the
/// `pairingCode` against an outstanding invite, mints a long-lived
/// `bearerToken`, and returns it via `PairResult`.
public struct PairRequest: Codable, Equatable, Sendable {
    public let pairingCode: String
    public let deviceName: String
    public let deviceId: String
    public let apnsToken: String?    // hex-encoded APNs device token, optional at first
    public let osVersion: String
    public let appVersion: String

    public init(pairingCode: String, deviceName: String, deviceId: String, apnsToken: String?, osVersion: String, appVersion: String) {
        self.pairingCode = pairingCode
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.apnsToken = apnsToken
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
}

public struct PairResult: Codable, Equatable, Sendable {
    public let bearerToken: String   // device presents on every subsequent connect
    public let macId: String
    public let macName: String

    public init(bearerToken: String, macId: String, macName: String) {
        self.bearerToken = bearerToken
        self.macId = macId
        self.macName = macName
    }
}

/// Sent on every reconnect after pairing.
public struct AuthRequest: Codable, Equatable, Sendable {
    public let bearerToken: String
    public let deviceId: String
    public let apnsToken: String?    // updated if iOS rotated it
    public let appVersion: String

    public init(bearerToken: String, deviceId: String, apnsToken: String?, appVersion: String) {
        self.bearerToken = bearerToken
        self.deviceId = deviceId
        self.apnsToken = apnsToken
        self.appVersion = appVersion
    }
}

public struct AuthResult: Codable, Equatable, Sendable {
    public let macName: String
    public let serverTime: Date

    public init(macName: String, serverTime: Date) {
        self.macName = macName
        self.serverTime = serverTime
    }
}

// MARK: - Live messages

/// Anything that can flow between Mac and device. Tagged enums for clarity
/// on the wire; both ends use the `kind` discriminator.
public enum WireMessage: Codable, Equatable, Sendable {
    case hello(AuthRequest)
    case helloOk(AuthResult)
    case helloError(String)

    case pair(PairRequest)
    case paired(PairResult)
    case pairError(String)

    case event(ServerEvent)
    case command(ClientCommand)
    case ack(commandId: String, ok: Bool, message: String?)
}

public enum ServerEvent: Codable, Equatable, Sendable {
    case sessionsSnapshot([SessionSummary])
    case sessionUpdate(SessionSummary)
    case approvalRequest(ApprovalRequest)
    case approvalCancelled(approvalId: String)
    case transcriptChunk(sessionId: String, text: String, at: Date)
}

public enum ClientCommand: Codable, Equatable, Sendable {
    case approve(approvalId: String, response: ApprovalResponse)
    case sendInput(sessionId: String, text: String, commandId: String)
    case requestSnapshot
    case ping
}

public enum ApprovalResponse: String, Codable, Equatable, Sendable {
    case allow
    case deny
    case allowAndDontAskAgain
}

// MARK: - Domain payloads

public struct SessionSummary: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectId: String
    public let projectName: String
    public let taskTitle: String?
    public let branch: String
    public let status: SessionStatusPayload
    public let needsInput: Bool
    public let updatedAt: Date

    public init(id: String, projectId: String, projectName: String, taskTitle: String?, branch: String, status: SessionStatusPayload, needsInput: Bool, updatedAt: Date) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.taskTitle = taskTitle
        self.branch = branch
        self.status = status
        self.needsInput = needsInput
        self.updatedAt = updatedAt
    }
}

public enum SessionStatusPayload: String, Codable, Equatable, Hashable, Sendable {
    case starting, running, waitingForInput, idle, finished, archived, prOpen, merged, failed
}

/// A rich approval request. `prompt` carries Claude Code's full message;
/// `toolCall` (when present) names the tool and serialised arguments so the
/// iOS UI can render "Allow `Bash(rm -rf node_modules)`".
public struct ApprovalRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let projectName: String
    public let taskTitle: String?
    public let prompt: String
    public let toolCall: ToolCallSummary?
    public let createdAt: Date

    public init(id: String, sessionId: String, projectName: String, taskTitle: String?, prompt: String, toolCall: ToolCallSummary?, createdAt: Date) {
        self.id = id
        self.sessionId = sessionId
        self.projectName = projectName
        self.taskTitle = taskTitle
        self.prompt = prompt
        self.toolCall = toolCall
        self.createdAt = createdAt
    }
}

public struct ToolCallSummary: Codable, Equatable, Sendable {
    public let toolName: String
    public let argumentSummary: String   // e.g. `rm -rf node_modules` or `https://api.example.com/foo`
    public let isDestructive: Bool
    public init(toolName: String, argumentSummary: String, isDestructive: Bool) {
        self.toolName = toolName
        self.argumentSummary = argumentSummary
        self.isDestructive = isDestructive
    }
}
