import XCTest
import OrzMCRemoteHosting

@testable import OrzMC

/// P2-7 第 1 步：exaroton 适配器把模型挂到供应商抽象层上（行为不变，只是映射）。
@MainActor
final class ExarotonHostingProviderTests: XCTestCase {

    private func makeServer(
        id: String?,
        name: String? = "测试服",
        address: String? = nil,
        host: String? = "example.com",
        port: Int32? = 25565,
        status: ServerStatus
    ) -> ExarotonServer {
        .init(
            id: id,
            name: name,
            address: address,
            motd: nil,
            status: .init(rawValue: status.rawValue),
            host: host,
            port: port,
            players: .init(max: 20, count: 0, list: []),
            software: nil,
            shared: false
        )
    }

    func testProviderKindIsExaroton() {
        let model = ExarotonServerModel()
        XCTAssertEqual(model.hostingProvider.kind, .exaroton)
    }

    func testListInstancesMapsServersAndUsesEffectiveStatus() async throws {
        let model = ExarotonServerModel()
        model.servers = [makeServer(id: "srv1", status: .OFFLINE)]
        // WS 推送优先于 HTTP 快照（唯一状态来源，见 docs/remote-status-source.md）
        model.liveStatuses["srv1"] = .LOADING

        let instances = try await model.hostingProvider.listInstances()

        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].id, RemoteInstanceID(provider: .exaroton, rawValue: "srv1"))
        XCTAssertEqual(instances[0].provider, .exaroton)
        XCTAssertEqual(instances[0].name, "测试服")
        XCTAssertEqual(instances[0].state, .starting, "LOADING 应归一化成过渡态 starting")
        XCTAssertEqual(instances[0].address, "example.com:25565", "没有静态地址时用动态地址")
    }

    func testStaticAddressIsPreferredOverDynamic() async throws {
        let model = ExarotonServerModel()
        model.servers = [
            makeServer(id: "srv1", address: "play.example.com", host: "temp.exaroton.me", status: .ONLINE)
        ]

        let instances = try await model.hostingProvider.listInstances()
        XCTAssertEqual(instances[0].address, "play.example.com:25565")
    }

    /// 服务端没给状态的实例按 `unknown` 处理（界面显示"状态未知"、禁用动作）。
    func testMissingStatusFallsBackToUnknown() async throws {
        let model = ExarotonServerModel()
        model.servers = [
            makeServer(id: "srv1", status: .UNKNOWN),
            .init(id: "srv2", name: "无状态", address: nil, motd: nil, status: nil,
                  host: "h", port: 1, players: .init(max: 1, count: 0, list: []),
                  software: nil, shared: false)
        ]

        let instances = try await model.hostingProvider.listInstances()
        XCTAssertEqual(instances.map(\.state), [.unknown, .unknown])
    }

    /// 没有 id 的实例无法做键（状态中心、动作都以 id 为准），直接跳过而不是造一个假 id。
    func testServersWithoutIDAreSkipped() async throws {
        let model = ExarotonServerModel()
        model.servers = [makeServer(id: nil, status: .ONLINE)]

        let instances = try await model.hostingProvider.listInstances()
        XCTAssertTrue(instances.isEmpty)
    }

    /// 交错的多账号/多供应商场景：exaroton 的适配器只能操作 exaroton 的实例。
    func testPerformRejectsForeignInstance() async {
        let model = ExarotonServerModel()
        model.errorMessage = nil

        do {
            try await model.hostingProvider.perform(
                .start,
                on: RemoteInstanceID(provider: .mcsmanager, rawValue: "m1")
            )
            XCTFail("应该抛 wrongProvider")
        } catch {
            XCTAssertEqual(
                error as? RemoteHostingError,
                .wrongProvider(expected: .exaroton, actual: .mcsmanager)
            )
        }
        XCTAssertNil(model.errorMessage, "被拒绝的请求不该在模型上留下错误（不碰模型）")
    }

    /// 现有动作是"返回 Bool + 把原因写进 actionErrors"；适配层要把 false 变成错误，
    /// 否则调用方会误以为请求提交成功。用 gate 占住实例来构造"没被接受"，不碰网络。
    func testPerformSurfacesRejectedAction() async {
        let model = ExarotonServerModel()
        XCTAssertTrue(model.gate.beginAction(serverID: "srv1"))

        do {
            try await model.hostingProvider.perform(
                .start,
                on: RemoteInstanceID(provider: .exaroton, rawValue: "srv1")
            )
            XCTFail("实例在途时应抛 actionFailed")
        } catch {
            XCTAssertEqual(error as? RemoteHostingError, .actionFailed(.start))
        }
    }
}


@MainActor
final class ExarotonAccountsTests: XCTestCase {
    private final class MemoryCredentials {
        var tokens: [String: String] = [:]
        var failWrites = false
        func save(_ token: String, key: String) throws {
            if failWrites { throw NSError(domain: "test", code: 1) }
            tokens[key] = token
        }
    }

    func testLegacyMigrationAndAccountIsolation() throws {
        let suite = "exaroton-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        store.tokens[ExarotonServerModel.accountTokenPersistentKey] = "legacy-token"
        let model = ExarotonAccountsModel(defaults: defaults,
            loadToken: { store.tokens[$0] }, saveToken: { try store.save($0, key: $1) },
            deleteToken: { store.tokens[$0] = nil })
        XCTAssertEqual(model.accounts.count, 1)
        let first = try XCTUnwrap(model.accounts.first)
        XCTAssertEqual(model.models[first.id]?.token, "legacy-token")
        XCTAssertNil(store.tokens[ExarotonServerModel.accountTokenPersistentKey])
        XCTAssertTrue(model.save(id: nil, label: "Second", token: "second-token"))
        let second = try XCTUnwrap(model.accounts.last)
        XCTAssertFalse(model.save(id: nil, label: "Duplicate", token: "second-token"))
        let untouched = try XCTUnwrap(model.models[second.id])
        XCTAssertTrue(model.save(id: first.id, label: "Renamed", token: ""))
        XCTAssertTrue(model.models[second.id] === untouched)
        model.remove(first.id)
        XCTAssertEqual(model.accounts.map(\.id), [second.id])
        XCTAssertTrue(model.models[second.id] === untouched)
        XCTAssertEqual(untouched.token, "second-token")
    }

    func testAutomaticNameAndExplicitNameArePreserved() async throws {
        let suite = "exaroton-names-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let model = ExarotonAccountsModel(defaults: defaults,
            loadToken: { store.tokens[$0] }, saveToken: { try store.save($0, key: $1) },
            deleteToken: { store.tokens[$0] = nil })
        XCTAssertTrue(model.save(id: nil, label: "", token: "token-a"))
        let id = try XCTUnwrap(model.accounts.first?.id)
        await model.resolveDefaultName(for: id, lookup: { _ in "  Actual account  " })
        XCTAssertEqual(model.accounts.first?.label, "Actual account")
        XCTAssertTrue(model.save(id: id, label: "Actual account", token: "token-b"))
        await model.resolveDefaultName(for: id, lookup: { _ in "Other account" })
        XCTAssertEqual(model.accounts.first?.label, "Other account")
        await model.resolveDefaultName(for: id, lookup: { _ in
            XCTAssertTrue(model.save(id: id, label: "My label", token: ""))
            return "Stale response"
        })
        XCTAssertEqual(model.accounts.first?.label, "My label")
        await model.resolveDefaultName(for: id, lookup: { _ in "Should not replace" })
        XCTAssertEqual(model.accounts.first?.label, "My label")
        let restored = ExarotonAccountsModel(defaults: defaults,
            loadToken: { store.tokens[$0] }, saveToken: { try store.save($0, key: $1) },
            deleteToken: { store.tokens[$0] = nil })
        XCTAssertEqual(restored.accounts.first?.label, "My label")
    }

    func testLegacyDefaultCanResolveToProviderName() async throws {
        let suite = "exaroton-legacy-name-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let id = UUID()
        let legacy = "[{\"id\":\"\(id.uuidString)\",\"label\":\"exaroton\"}]"
        defaults.set(Data(legacy.utf8), forKey: ExarotonAccountsModel.accountsKey)
        store.tokens[ExarotonAccountsModel.tokenKey(id)] = "legacy-token"
        let model = ExarotonAccountsModel(defaults: defaults,
            loadToken: { store.tokens[$0] }, saveToken: { try store.save($0, key: $1) },
            deleteToken: { store.tokens[$0] = nil })
        XCTAssertNotEqual(model.accounts.first?.displayName, "exaroton")
        await model.resolveDefaultName(for: id, lookup: { _ in "exaroton" })
        XCTAssertEqual(model.accounts.first?.displayName, "exaroton")
    }

    func testFailedMigrationKeepsLegacyCredential() throws {
        let suite = "exaroton-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        store.tokens[ExarotonServerModel.accountTokenPersistentKey] = "legacy-token"
        store.failWrites = true
        let model = ExarotonAccountsModel(defaults: defaults,
            loadToken: { store.tokens[$0] }, saveToken: { try store.save($0, key: $1) },
            deleteToken: { store.tokens[$0] = nil })
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(store.tokens[ExarotonServerModel.accountTokenPersistentKey], "legacy-token")
        XCTAssertNil(defaults.data(forKey: ExarotonAccountsModel.accountsKey))
    }
}
