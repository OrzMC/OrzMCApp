import XCTest
@testable import OrzMCRemoteHosting

final class RemoteServerListPolicyTests: XCTestCase {

    private func instance(
        _ rawID: String,
        _ name: String,
        address: String? = nil,
        state: RemoteServerState = .offline,
        provider: ProviderKind = .exaroton
    ) -> RemoteInstanceSummary {
        RemoteInstanceSummary(provider: provider, rawID: rawID, name: name, address: address, state: state)
    }

    func testVisibleServersFilterByNameAndAddress() {
        let instances = [
            instance("1", "Survival", address: "play.example.com"),
            instance("2", "Creative", address: "build.example.com")
        ]
        let policy = RemoteServerListPolicy()

        XCTAssertEqual(policy.visibleInstances(from: instances, searchText: "surv"), [instances[0]])
        XCTAssertEqual(policy.visibleInstances(from: instances, searchText: "build"), [instances[1]])
        XCTAssertEqual(policy.visibleInstances(from: instances, searchText: "   "), instances)
    }

    /// 搜索**不按供应商过滤**（多供应商是按供应商分组展示，不是筛选）。
    func testSearchMatchesAcrossProviders() {
        let instances = [
            instance("1", "Survival"),
            instance("2", "Survival 二服", provider: .mcsmanager)
        ]
        let policy = RemoteServerListPolicy()

        XCTAssertEqual(policy.visibleInstances(from: instances, searchText: "survival"), instances)
    }

    func testActionAvailability() {
        let policy = RemoteServerListPolicy()

        XCTAssertTrue(policy.canPerform(.start, on: .offline))
        XCTAssertTrue(policy.canPerform(.stop, on: .online))
        XCTAssertTrue(policy.canPerform(.restart, on: .online))
        XCTAssertFalse(policy.canPerform(.start, on: .starting))
        XCTAssertFalse(policy.canPerform(.stop, on: .offline))
        // 强杀：只要没停就能点（面板前端 `condition: () => !isStopped`）——
        // 启动中/停止中/重启中/未知都给，正是为了打破"卡在停止中"。
        XCTAssertTrue(policy.canPerform(.kill, on: .online))
        XCTAssertTrue(policy.canPerform(.kill, on: .starting))
        XCTAssertTrue(policy.canPerform(.kill, on: .stopping))
        XCTAssertTrue(policy.canPerform(.kill, on: .restarting))
        XCTAssertTrue(policy.canPerform(.kill, on: .unknown))
        XCTAssertFalse(policy.canPerform(.kill, on: .offline))

        // 过渡态一律不允许：exaroton 会拒绝（真机实测启动中/停止中/重启中点了都报错）
        XCTAssertFalse(policy.canPerform(.stop, on: .starting))
        XCTAssertFalse(policy.canPerform(.restart, on: .starting))
        XCTAssertFalse(policy.canPerform(.stop, on: .stopping))
        XCTAssertFalse(policy.canPerform(.start, on: .restarting))
        XCTAssertFalse(policy.canPerform(.restart, on: .unknown))
    }
}
