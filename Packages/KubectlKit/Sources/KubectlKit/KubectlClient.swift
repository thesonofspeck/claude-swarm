import Foundation

/// High-level façade over `kubectl`. Decodes the JSON we care about
/// into Sendable models; everything else (logs, port-forward, exec)
/// flows through the runner directly.
public actor KubectlClient {
    public let runner: KubectlRunner
    private let isoFormatter: ISO8601DateFormatter

    public init(runner: KubectlRunner = KubectlRunner()) {
        self.runner = runner
        self.isoFormatter = ISO8601DateFormatter()
    }

    // MARK: - Contexts

    public func contexts() async throws -> [K8sContext] {
        // `kubectl config view -o json` is the only stable JSON source —
        // `get-contexts` doesn't support `-o json`.
        let raw = try await runner.run(["config", "view", "-o", "json", "--minify=false"])
        guard let data = raw.stdout.data(using: .utf8) else { return [] }

        struct Cfg: Decodable {
            struct Ctx: Decodable {
                struct Inner: Decodable {
                    let cluster: String
                    let user: String
                    let namespace: String?
                }
                let name: String
                let context: Inner
            }
            let contexts: [Ctx]?
            let currentContext: String?

            enum CodingKeys: String, CodingKey {
                case contexts
                case currentContext = "current-context"
            }
        }

        let cfg = try JSONDecoder().decode(Cfg.self, from: data)
        let current = cfg.currentContext
        return (cfg.contexts ?? []).map { c in
            K8sContext(
                name: c.name,
                cluster: c.context.cluster,
                user: c.context.user,
                namespace: c.context.namespace,
                isCurrent: c.name == current
            )
        }
    }

    // MARK: - Deployments

    public func deployments(context: String?, namespace: String?) async throws -> [K8sDeployment] {
        let list: K8sList<RawDeployment> = try await runner.runJSON(
            ["get", "deployments"], context: context, namespace: namespace
        )
        return list.items.map(makeDeployment(_:))
    }

    private func makeDeployment(_ raw: RawDeployment) -> K8sDeployment {
        let desired = raw.spec?.replicas ?? raw.status?.replicas ?? 0
        let ready = raw.status?.readyReplicas ?? 0
        let updated = raw.status?.updatedReplicas ?? 0
        let available = raw.status?.availableReplicas ?? 0
        let image = raw.spec?.template?.spec?.containers?.first?.image
        let created = raw.metadata.creationTimestamp.flatMap { isoFormatter.date(from: $0) }

        let status: K8sRolloutStatus
        if desired == 0 {
            status = .unknown
        } else if ready < desired {
            // If a Progressing condition exists with status True, prefer "progressing".
            let progressing = raw.status?.conditions?.contains {
                $0.type == "Progressing" && $0.status == "True" && $0.reason != "NewReplicaSetAvailable"
            } ?? false
            status = progressing ? .progressing : .degraded
        } else if updated < desired {
            status = .progressing
        } else {
            status = .healthy
        }

        return K8sDeployment(
            namespace: raw.metadata.namespace,
            name: raw.metadata.name,
            replicas: desired,
            readyReplicas: ready,
            updatedReplicas: updated,
            availableReplicas: available,
            image: image,
            creationTimestamp: created,
            status: status
        )
    }

    // MARK: - Pods

    public func pods(context: String?, namespace: String?, selector: String? = nil) async throws -> [K8sPod] {
        var args = ["get", "pods"]
        if let selector, !selector.isEmpty {
            args.append("-l")
            args.append(selector)
        }
        let list: K8sList<RawPod> = try await runner.runJSON(
            args, context: context, namespace: namespace
        )
        return list.items.map(makePod(_:))
    }

    private func makePod(_ raw: RawPod) -> K8sPod {
        let phase = raw.status?.phase.flatMap(K8sPodPhase.init(rawValue:)) ?? .unknown
        let restartCount = raw.status?.containerStatuses?.reduce(0) { $0 + $1.restartCount } ?? 0
        let containers = raw.spec.containers.map(\.name)
        let created = raw.metadata.creationTimestamp.flatMap { isoFormatter.date(from: $0) }
        return K8sPod(
            namespace: raw.metadata.namespace,
            name: raw.metadata.name,
            phase: phase,
            nodeName: raw.spec.nodeName,
            podIP: raw.status?.podIP,
            restartCount: restartCount,
            containers: containers,
            creationTimestamp: created
        )
    }

    // MARK: - Services

    public func services(context: String?, namespace: String?) async throws -> [K8sService] {
        let list: K8sList<RawService> = try await runner.runJSON(
            ["get", "services"], context: context, namespace: namespace
        )
        return list.items.map(makeService(_:))
    }

    private func makeService(_ raw: RawService) -> K8sService {
        let portStrings: [String] = (raw.spec?.ports ?? []).map { p in
            let target = p.targetPort?.stringValue ?? String(p.port)
            let proto = p.`protocol` ?? "TCP"
            if target == String(p.port) {
                return "\(p.port)/\(proto)"
            }
            return "\(p.port)→\(target)/\(proto)"
        }
        let external: String? = {
            if let ip = raw.status?.loadBalancer?.ingress?.first?.ip { return ip }
            if let host = raw.status?.loadBalancer?.ingress?.first?.hostname { return host }
            return nil
        }()
        return K8sService(
            namespace: raw.metadata.namespace,
            name: raw.metadata.name,
            type: raw.spec?.type ?? "ClusterIP",
            clusterIP: raw.spec?.clusterIP,
            externalIP: external,
            ports: portStrings
        )
    }

    // MARK: - Actions

    /// `kubectl rollout restart deployment/<name>`. Idiomatic in-place
    /// restart that respects the deployment's update strategy.
    public func restartDeployment(name: String, context: String?, namespace: String?) async throws {
        _ = try await runner.run(
            ["rollout", "restart", "deployment/\(name)"],
            context: context, namespace: namespace
        )
    }

    public func rolloutStatus(name: String, context: String?, namespace: String?) async throws -> String {
        let r = try await runner.run(
            ["rollout", "status", "deployment/\(name)", "--watch=false"],
            context: context, namespace: namespace
        )
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func scaleDeployment(name: String, replicas: Int, context: String?, namespace: String?) async throws {
        _ = try await runner.run(
            ["scale", "deployment/\(name)", "--replicas=\(replicas)"],
            context: context, namespace: namespace
        )
    }

    /// One-shot logs read (no follow). Caller can pass `tail` to limit
    /// volume — defaults to the last 500 lines.
    public func logs(
        pod: String,
        container: String? = nil,
        context: String?,
        namespace: String?,
        tail: Int = 500
    ) async throws -> String {
        var args = ["logs", pod, "--tail=\(tail)"]
        if let container, !container.isEmpty {
            args.append("-c")
            args.append(container)
        }
        let r = try await runner.run(args, context: context, namespace: namespace, timeout: 60)
        return r.stdout
    }

    /// `kubectl logs -f` streamed line-by-line. Cancel the consuming
    /// task to stop following.
    nonisolated public func streamLogs(
        pod: String,
        container: String? = nil,
        context: String?,
        namespace: String?,
        tail: Int = 500
    ) -> AsyncThrowingStream<String, Error> {
        var args = ["logs", pod, "-f", "--tail=\(tail)"]
        if let container, !container.isEmpty {
            args.append("-c")
            args.append(container)
        }
        return runner.runStreaming(args, context: context, namespace: namespace)
    }

    public func deletePod(name: String, context: String?, namespace: String?) async throws {
        _ = try await runner.run(
            ["delete", "pod", name],
            context: context, namespace: namespace
        )
    }
}
