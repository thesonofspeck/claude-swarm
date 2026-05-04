import XCTest
@testable import KubectlKit

final class KubectlKitTests: XCTestCase {
    func testDeploymentDecodingHealthy() throws {
        let json = """
        {
          "items": [
            {
              "metadata": {"name":"api","namespace":"prod","creationTimestamp":"2026-01-01T00:00:00Z"},
              "spec": {"replicas": 3, "template": {"spec":{"containers":[{"image":"acme/api:1.2.3"}]}}},
              "status": {"replicas": 3, "readyReplicas": 3, "updatedReplicas": 3, "availableReplicas": 3}
            }
          ]
        }
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(K8sList<RawDeployment>.self, from: json)
        XCTAssertEqual(list.items.count, 1)
        let raw = list.items[0]
        XCTAssertEqual(raw.metadata.name, "api")
        XCTAssertEqual(raw.spec?.replicas, 3)
        XCTAssertEqual(raw.spec?.template?.spec?.containers?.first?.image, "acme/api:1.2.3")
    }

    func testPodPhaseDecoding() throws {
        let json = """
        {
          "items": [
            {
              "metadata": {"name":"api-abc","namespace":"prod"},
              "spec": {"containers":[{"name":"api"}], "nodeName":"ip-10-0-1-2"},
              "status": {"phase":"Running","podIP":"10.0.1.2","containerStatuses":[{"restartCount":2}]}
            }
          ]
        }
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(K8sList<RawPod>.self, from: json)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].status?.phase, "Running")
        XCTAssertEqual(list.items[0].status?.containerStatuses?.first?.restartCount, 2)
    }

    func testServicePortFormatting() throws {
        let json = """
        {
          "items": [
            {
              "metadata": {"name":"api","namespace":"prod"},
              "spec": {"type":"LoadBalancer","clusterIP":"10.0.0.1","ports":[
                {"port":80,"targetPort":8080,"protocol":"TCP"}
              ]},
              "status": {"loadBalancer":{"ingress":[{"hostname":"abc.elb.amazonaws.com"}]}}
            }
          ]
        }
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(K8sList<RawService>.self, from: json)
        XCTAssertEqual(list.items[0].spec?.ports?.first?.port, 80)
        XCTAssertEqual(list.items[0].spec?.ports?.first?.targetPort?.stringValue, "8080")
        XCTAssertEqual(list.items[0].status?.loadBalancer?.ingress?.first?.hostname, "abc.elb.amazonaws.com")
    }

    func testTargetPortStringDecoding() throws {
        let json = """
        {"port":80,"targetPort":"http","protocol":"TCP"}
        """.data(using: .utf8)!
        let port = try JSONDecoder().decode(RawService.Spec.Port.self, from: json)
        XCTAssertEqual(port.targetPort?.stringValue, "http")
    }
}
