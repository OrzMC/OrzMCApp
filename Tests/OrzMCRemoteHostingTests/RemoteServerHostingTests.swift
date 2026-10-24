import XCTest
@testable import OrzMCRemoteHosting

final class RemoteServerHostingTests: XCTestCase {
    func testVisibleServersFilterByNameAndAddress() {
        let servers = [
            RemoteServerSummary(id: .init("1"), name: "Survival", address: "play.example.com", state: .online),
            RemoteServerSummary(id: .init("2"), name: "Creative", address: "build.example.com", state: .offline)
        ]
        let policy = RemoteServerListPolicy()

        XCTAssertEqual(policy.visibleServers(from: servers, searchText: "surv"), [servers[0]])
        XCTAssertEqual(policy.visibleServers(from: servers, searchText: "build"), [servers[1]])
        XCTAssertEqual(policy.visibleServers(from: servers, searchText: "   "), servers)
    }

    func testActionAvailability() {
        let policy = RemoteServerListPolicy()

        XCTAssertTrue(policy.canPerform(.start, on: .offline))
        XCTAssertTrue(policy.canPerform(.stop, on: .online))
        XCTAssertTrue(policy.canPerform(.restart, on: .online))
        XCTAssertFalse(policy.canPerform(.start, on: .starting))
        XCTAssertFalse(policy.canPerform(.stop, on: .offline))
        // 启动中可以取消（真机验收反馈：点了启动只能干等）
        XCTAssertTrue(policy.canPerform(.stop, on: .starting))
        XCTAssertFalse(policy.canPerform(.restart, on: .starting))
        XCTAssertFalse(policy.canPerform(.restart, on: .unknown))
    }
}
