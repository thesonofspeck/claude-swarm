import Foundation
import NIO
import NIOHTTP1
import NIOPosix
import ArgumentParser
import ApnsClient

// MARK: - CLI

struct SwarmPushRelay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swarm-push-relay",
        abstract: "Tiny APNs relay that holds a single .p8 key and forwards pushes from Mac apps over your VPN."
    )

    @Option(name: .long, help: "Path to the .p8 APNs auth key.")
    var p8: String

    @Option(name: .long, help: "Apple Developer team id (10 chars).")
    var team: String

    @Option(name: .long, help: ".p8 key id (10 chars).")
    var key: String

    @Option(name: .long, help: "iOS app bundle id (apns-topic).")
    var bundle: String

    @Option(name: .long, help: "Shared secret used to HMAC-sign incoming requests.")
    var sharedSecret: String

    @Option(name: .long, help: "APNs environment: production or sandbox.")
    var environment: String = "production"

    @Option(name: .long, help: "Listen port.")
    var port: Int = 8443

    @Option(name: .long, help: "Bind address.")
    var bind: String = "0.0.0.0"

    func run() async throws {
        let pem = try String(contentsOfFile: p8, encoding: .utf8)
        let env: ApnsConfig.Environment = environment == "sandbox" ? .sandbox : .production
        let config = ApnsConfig(
            teamId: team, keyId: key,
            bundleId: bundle, environment: env, enabled: true
        )
        let apns = ApnsClient(config: config, p8Pem: pem)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(RelayHandler(
                        apns: apns,
                        sharedSecret: sharedSecret
                    ))
                }
            }

        let channel = try await bootstrap.bind(host: bind, port: port).get()
        FileHandle.standardError.write(Data("swarm-push-relay listening on \(bind):\(port)\n".utf8))
        try await channel.closeFuture.get()
    }
}

await SwarmPushRelay.main()

// MARK: - Handler

final class RelayHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let apns: ApnsClient
    let sharedSecret: String
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?

    init(apns: ApnsClient, sharedSecret: String) {
        self.apns = apns
        self.sharedSecret = sharedSecret
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            self.body = nil
        case .body(var chunk):
            if body == nil {
                body = chunk
            } else {
                body?.writeBuffer(&chunk)
            }
        case .end:
            handleRequest(context: context)
        }
    }

    private func handleRequest(context: ChannelHandlerContext) {
        guard let head else {
            respond(context: context, status: .badRequest, body: "no headers")
            return
        }

        switch (head.method, head.uri) {
        case (.GET, "/health"):
            respond(context: context, status: .ok, body: "ok")
        case (.POST, "/push"):
            handlePush(context: context, head: head)
        default:
            respond(context: context, status: .notFound, body: "")
        }
    }

    private func handlePush(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let bodyData: Data
        if let body, let bytes = body.getBytes(at: 0, length: body.readableBytes) {
            bodyData = Data(bytes)
        } else {
            bodyData = Data()
        }

        guard let auth = head.headers.first(name: "Authorization"),
              let timestamp = head.headers.first(name: "X-Swarm-Timestamp"),
              auth.hasPrefix("SwarmRelay ") else {
            respond(context: context, status: .unauthorized, body: "missing signature")
            return
        }
        let signature = String(auth.dropFirst("SwarmRelay ".count))
        let expected = RelayPushSender.hmacHex(secret: sharedSecret, timestamp: timestamp, body: bodyData)
        guard constantTimeEqual(signature, expected) else {
            respond(context: context, status: .unauthorized, body: "bad signature")
            return
        }
        // Reject requests older than 5 minutes to limit replay window.
        if let unix = Int(timestamp) {
            let age = Int(Date().timeIntervalSince1970) - unix
            if age > 300 || age < -60 {
                respond(context: context, status: .unauthorized, body: "stale timestamp")
                return
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let token = json["deviceToken"] as? String,
              let payload = json["payload"] as? [String: Any] else {
            respond(context: context, status: .badRequest, body: "bad json")
            return
        }
        let collapseId = json["collapseId"] as? String

        // Re-serialize the payload to Data once so the Sendable Task
        // closure doesn't have to capture a non-Sendable [String: Any].
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            respond(context: context, status: .badRequest, body: "bad payload")
            return
        }
        let loop = context.eventLoop
        let promise = loop.makePromise(of: Void.self)
        Task {
            do {
                try await apns.send(payload: payloadData, to: token, collapseId: collapseId)
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        promise.futureResult.whenComplete { [self] result in
            switch result {
            case .success:
                respond(context: context, status: .ok, body: "")
            case .failure(let error):
                respond(context: context, status: .badGateway, body: "\(error)")
            }
        }
    }

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        headers.add(name: "Content-Type", value: "text/plain")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ad = Data(a.utf8)
        let bd = Data(b.utf8)
        guard ad.count == bd.count else { return false }
        var result: UInt8 = 0
        for i in 0..<ad.count { result |= ad[i] ^ bd[i] }
        return result == 0
    }
}
