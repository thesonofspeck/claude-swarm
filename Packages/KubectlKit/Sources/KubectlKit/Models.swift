import Foundation

/// A kubeconfig context available on the user's machine. Sourced from
/// `kubectl config get-contexts -o json` (we re-shape into this struct).
public struct K8sContext: Sendable, Hashable, Identifiable, Codable {
    public let name: String
    public let cluster: String
    public let user: String
    public let namespace: String?
    public let isCurrent: Bool

    public var id: String { name }

    public init(name: String, cluster: String, user: String, namespace: String?, isCurrent: Bool) {
        self.name = name
        self.cluster = cluster
        self.user = user
        self.namespace = namespace
        self.isCurrent = isCurrent
    }
}

public enum K8sRolloutStatus: String, Sendable, Codable {
    case healthy        // ready == desired, no progressing condition
    case progressing    // an update is rolling
    case degraded       // ready < desired
    case unknown
}

/// One Deployment summary, distilled from `kubectl get deploy -o json`.
public struct K8sDeployment: Sendable, Hashable, Identifiable, Codable {
    public let namespace: String
    public let name: String
    public let replicas: Int
    public let readyReplicas: Int
    public let updatedReplicas: Int
    public let availableReplicas: Int
    public let image: String?
    public let creationTimestamp: Date?
    public let status: K8sRolloutStatus

    public var id: String { "\(namespace)/\(name)" }

    public init(
        namespace: String,
        name: String,
        replicas: Int,
        readyReplicas: Int,
        updatedReplicas: Int,
        availableReplicas: Int,
        image: String?,
        creationTimestamp: Date?,
        status: K8sRolloutStatus
    ) {
        self.namespace = namespace
        self.name = name
        self.replicas = replicas
        self.readyReplicas = readyReplicas
        self.updatedReplicas = updatedReplicas
        self.availableReplicas = availableReplicas
        self.image = image
        self.creationTimestamp = creationTimestamp
        self.status = status
    }
}

public enum K8sPodPhase: String, Sendable, Codable {
    case pending = "Pending"
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case unknown = "Unknown"
}

public struct K8sPod: Sendable, Hashable, Identifiable, Codable {
    public let namespace: String
    public let name: String
    public let phase: K8sPodPhase
    public let nodeName: String?
    public let podIP: String?
    public let restartCount: Int
    public let containers: [String]
    public let creationTimestamp: Date?

    public var id: String { "\(namespace)/\(name)" }

    public init(
        namespace: String,
        name: String,
        phase: K8sPodPhase,
        nodeName: String?,
        podIP: String?,
        restartCount: Int,
        containers: [String],
        creationTimestamp: Date?
    ) {
        self.namespace = namespace
        self.name = name
        self.phase = phase
        self.nodeName = nodeName
        self.podIP = podIP
        self.restartCount = restartCount
        self.containers = containers
        self.creationTimestamp = creationTimestamp
    }
}

public struct K8sService: Sendable, Hashable, Identifiable, Codable {
    public let namespace: String
    public let name: String
    public let type: String
    public let clusterIP: String?
    public let externalIP: String?
    public let ports: [String]

    public var id: String { "\(namespace)/\(name)" }

    public init(
        namespace: String,
        name: String,
        type: String,
        clusterIP: String?,
        externalIP: String?,
        ports: [String]
    ) {
        self.namespace = namespace
        self.name = name
        self.type = type
        self.clusterIP = clusterIP
        self.externalIP = externalIP
        self.ports = ports
    }
}

// MARK: - Decoding helpers — raw kubectl JSON shapes

/// Wraps a Kubernetes `List` response (`{ items: [...] }`).
struct K8sList<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
}

/// Subset of a Deployment as kubectl `-o json` returns it. We only
/// decode the fields we surface.
struct RawDeployment: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        let name: String
        let namespace: String
        let creationTimestamp: String?
    }
    struct Spec: Decodable, Sendable {
        struct Template: Decodable, Sendable {
            struct PodSpec: Decodable, Sendable {
                struct Container: Decodable, Sendable {
                    let image: String?
                }
                let containers: [Container]?
            }
            let spec: PodSpec?
        }
        let replicas: Int?
        let template: Template?
    }
    struct Status: Decodable, Sendable {
        struct Condition: Decodable, Sendable {
            let type: String
            let status: String
            let reason: String?
        }
        let replicas: Int?
        let readyReplicas: Int?
        let updatedReplicas: Int?
        let availableReplicas: Int?
        let conditions: [Condition]?
    }
    let metadata: Metadata
    let spec: Spec?
    let status: Status?
}

struct RawPod: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        let name: String
        let namespace: String
        let creationTimestamp: String?
    }
    struct Spec: Decodable, Sendable {
        struct Container: Decodable, Sendable {
            let name: String
        }
        let containers: [Container]
        let nodeName: String?
    }
    struct Status: Decodable, Sendable {
        struct ContainerStatus: Decodable, Sendable {
            let restartCount: Int
        }
        let phase: String?
        let podIP: String?
        let containerStatuses: [ContainerStatus]?
    }
    let metadata: Metadata
    let spec: Spec
    let status: Status?
}

struct RawService: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        let name: String
        let namespace: String
    }
    struct Spec: Decodable, Sendable {
        struct Port: Decodable, Sendable {
            let port: Int
            let targetPort: AnyCodable?
            let `protocol`: String?
            let name: String?
        }
        let type: String?
        let clusterIP: String?
        let ports: [Port]?
    }
    struct Status: Decodable, Sendable {
        struct LoadBalancer: Decodable, Sendable {
            struct Ingress: Decodable, Sendable {
                let ip: String?
                let hostname: String?
            }
            let ingress: [Ingress]?
        }
        let loadBalancer: LoadBalancer?
    }
    let metadata: Metadata
    let spec: Spec?
    let status: Status?
}

/// Loose container for `targetPort`, which may be a String or Int in the
/// k8s API. We only render it back as text.
struct AnyCodable: Decodable, Sendable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            stringValue = String(i)
        } else if let s = try? c.decode(String.self) {
            stringValue = s
        } else {
            stringValue = ""
        }
    }
}
