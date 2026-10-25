import XCTest
@testable import OrzMCRemoteHosting

/// P2-7 第 1 步：供应商抽象层（`ProviderKind` / `RemoteInstanceID` / `RemoteHostingProvider`）。
final class RemoteHostingProviderTests: XCTestCase {

    private func instance(
        _ rawID: String,
        provider: ProviderKind = .exaroton,
        name: String = "srv",
        state: RemoteServerState = .online
    ) -> RemoteInstanceSummary {
        RemoteInstanceSummary(provider: provider, rawID: rawID, name: name, address: nil, state: state)
    }

    // MARK: - 实例标识

    /// 两家供应商的原始 ID 撞车也必须能区分（状态中心/订阅/Keychain 都以它为键）。
    func testInstanceIDsAreNamespacedByProvider() {
        let exaroton = RemoteInstanceID(provider: .exaroton, rawValue: "42")
        let mcsmanager = RemoteInstanceID(provider: .mcsmanager, rawValue: "42")

        XCTAssertNotEqual(exaroton, mcsmanager)
        XCTAssertEqual(Set([exaroton, mcsmanager]).count, 2)
        XCTAssertEqual(exaroton.description, "exaroton:42")
    }

    func testSummaryProviderComesFromID() {
        let summary = instance("1", provider: .mcsmanager)
        XCTAssertEqual(summary.provider, .mcsmanager)
        XCTAssertEqual(summary.id, RemoteInstanceID(provider: .mcsmanager, rawValue: "1"))
    }

    /// 供应商枚举要能持久化（凭据/选中实例将来要落 UserDefaults）。
    func testProviderKindRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(ProviderKind.allCases)
        let decoded = try JSONDecoder().decode([ProviderKind].self, from: data)
        XCTAssertEqual(decoded, ProviderKind.allCases)
        XCTAssertEqual(ProviderKind(rawValue: "mcsmanager"), .mcsmanager)
    }

    // MARK: - 按供应商分组（维护者拍板：分组，不做过滤）

    func testGroupsByProviderInStableOrder() {
        let instances = [
            instance("m1", provider: .mcsmanager, name: "面板 A"),
            instance("e1", provider: .exaroton, name: "exaroton 一服"),
            instance("e2", provider: .exaroton, name: "exaroton 二服")
        ]

        let groups = RemoteHostingGrouping.groups(from: instances)

        // 分组顺序固定为 `ProviderKind.allCases`，与输入顺序无关。
        XCTAssertEqual(groups.map(\.provider), [.exaroton, .mcsmanager])
        // 组内保持输入顺序。
        XCTAssertEqual(groups[0].instances.map(\.id.rawValue), ["e1", "e2"])
        XCTAssertEqual(groups[1].instances.map(\.id.rawValue), ["m1"])
    }

    func testGroupsSkipProvidersWithoutInstances() {
        let groups = RemoteHostingGrouping.groups(from: [instance("m1", provider: .mcsmanager)])
        XCTAssertEqual(groups.map(\.provider), [.mcsmanager])
    }

    func testGroupsOnEmptyInputIsEmpty() {
        XCTAssertTrue(RemoteHostingGrouping.groups(from: []).isEmpty)
    }

    /// 多账号把同一实例拉了两遍时只留第一份：`ForEach` 的 `Identifiable` 不允许重复 id。
    func testGroupsDropDuplicateInstances() {
        let first = instance("e1", name: "第一份")
        let duplicate = instance("e1", name: "重复的那份")
        let groups = RemoteHostingGrouping.groups(from: [first, duplicate])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].instances, [first])
    }

    // MARK: - 闭包适配器

    func testClosureProviderForwardsListAndPerform() async throws {
        let recorder = ActionRecorder()
        let listed = [instance("m1", provider: .mcsmanager)]
        let provider = ClosureRemoteHostingProvider(
            kind: .mcsmanager,
            list: { listed },
            perform: { action, id in await recorder.record(action, id) }
        )

        XCTAssertEqual(provider.kind, .mcsmanager)
        let result = try await provider.listInstances()
        XCTAssertEqual(result.map(\.id.rawValue), ["m1"])

        try await provider.perform(.restart, on: RemoteInstanceID(provider: .mcsmanager, rawValue: "m1"))
        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.action, .restart)
        XCTAssertEqual(calls.first?.id.rawValue, "m1")
    }

    /// 交给错供应商时必须**直接拒绝**，连底层闭包都不能被调用。
    func testClosureProviderRejectsForeignInstanceWithoutCallingThrough() async {
        let recorder = ActionRecorder()
        let provider = ClosureRemoteHostingProvider(
            kind: .exaroton,
            list: { [] },
            perform: { action, id in await recorder.record(action, id) }
        )

        do {
            try await provider.perform(.start, on: RemoteInstanceID(provider: .mcsmanager, rawValue: "m1"))
            XCTFail("应该抛 wrongProvider")
        } catch {
            XCTAssertEqual(
                error as? RemoteHostingError,
                .wrongProvider(expected: .exaroton, actual: .mcsmanager)
            )
        }
        let calls = await recorder.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testClosureProviderPropagatesListErrors() async {
        let provider = ClosureRemoteHostingProvider(
            kind: .exaroton,
            list: { throw RemoteHostingError.actionFailed(.start) },
            perform: { _, _ in }
        )

        do {
            _ = try await provider.listInstances()
            XCTFail("错误应该透传")
        } catch {
            XCTAssertEqual(error as? RemoteHostingError, .actionFailed(.start))
        }
    }
}

/// 闭包适配器测试用的调用记录（跨隔离域安全）。
private actor ActionRecorder {
    struct Call: Equatable {
        let action: RemoteServerAction
        let id: RemoteInstanceID
    }

    private(set) var calls: [Call] = []

    func record(_ action: RemoteServerAction, _ id: RemoteInstanceID) {
        calls.append(Call(action: action, id: id))
    }
    /// 动作提交后的过渡态：界面靠它立刻给反馈，同时挡住连点（`canPerform` 对过渡态一律 false）。
    func testActionsMapToPendingStates() {
        XCTAssertEqual(RemoteServerAction.start.pendingState, .starting)
        XCTAssertEqual(RemoteServerAction.stop.pendingState, .stopping)
        XCTAssertEqual(RemoteServerAction.restart.pendingState, .restarting)

        // 过渡态本身必须挡住同一个动作（否则界面还能再点一次）。
        let policy = RemoteServerListPolicy()
        for action in RemoteServerAction.allCases {
            XCTAssertFalse(policy.canPerform(action, on: action.pendingState))
        }
    }
}
