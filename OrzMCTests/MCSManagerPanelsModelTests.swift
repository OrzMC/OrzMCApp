import XCTest
import OrzMCRemoteHosting

@testable import OrzMC

/// 内存版凭据存储（单测不碰 UserDefaults / Keychain）。
private final class InMemoryCredentialStore: MCSManagerCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPanels: [MCSManagerPanel] = []
    private var keys: [UUID: String] = [:]

    init(panels: [MCSManagerPanel] = [], keys: [UUID: String] = [:]) {
        storedPanels = panels
        self.keys = keys
    }

    func panels() -> [MCSManagerPanel] { lock.withLock { storedPanels } }
    func savePanels(_ panels: [MCSManagerPanel]) { lock.withLock { storedPanels = panels } }
    func apiKey(for id: UUID) -> String? { lock.withLock { keys[id] } }
    func saveAPIKey(_ apiKey: String, for id: UUID) { lock.withLock { keys[id] = apiKey } }
    func removeAPIKey(for id: UUID) { lock.withLock { keys[id] = nil } }
    func key(for id: UUID) -> String? { apiKey(for: id) }
}

/// 假面板：只实现 `/api/auth`（`verifyConnection` 用），并记录使用的 key。
private actor AuthOnlyPanelAPI: MCSManagerPanelAPI {
    private let key: String
    private let currentUserResult: Result<MCSManagerCurrentUser, Error>

    init(key: String, currentUser: Result<MCSManagerCurrentUser, Error>) {
        self.key = key
        currentUserResult = currentUser
    }

    func currentUser(advancedInstances: Bool) async throws -> MCSManagerCurrentUser {
        try currentUserResult.get()
    }

    func daemons() async throws -> [MCSManagerDaemon] { [] }
    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage {
        MCSManagerInstancePage(instances: [], maxPage: nil)
    }
}

/// 面板增 / 改 / 删 + 测试连接（P2-7 第 4 步之后的体验修补）。
@MainActor
final class MCSManagerPanelsModelTests: XCTestCase {

    private func makeModel(
        store: InMemoryCredentialStore,
        currentUser: Result<MCSManagerCurrentUser, Error> = .success(
            MCSManagerCurrentUser(permission: MCSManagerRole.user, instances: [])
        ),
        usedKeys: @escaping @Sendable (String) -> Void = { _ in }
    ) -> MCSManagerPanelsModel {
        MCSManagerPanelsModel(
            store: store,
            makeAPI: { _, key in
                usedKeys(key)
                return AuthOnlyPanelAPI(key: key, currentUser: currentUser)
            }
        )
    }

    // MARK: - 添加

    func testAddPanelStoresPanelAndKey() {
        let store = InMemoryCredentialStore()
        let model = makeModel(store: store)

        XCTAssertTrue(model.addPanel(label: "测试服", rawURL: " panel.example.com/ ", apiKey: " key123 "))

        XCTAssertEqual(model.panels.count, 1)
        XCTAssertEqual(model.panels.first?.label, "测试服")
        XCTAssertEqual(model.panels.first?.url.absoluteString, "https://panel.example.com")
        XCTAssertEqual(store.key(for: model.panels[0].id), "key123", "Key 要进（Keychain）存储，且去掉首尾空白")
        XCTAssertNotNil(model.model(for: model.panels[0].id), "面板要有自己的模型")
    }

    func testAddPanelRejectsInvalidURLAndEmptyKey() {
        let model = makeModel(store: InMemoryCredentialStore())

        XCTAssertFalse(model.addPanel(label: "", rawURL: "file:///etc/passwd", apiKey: "k"))
        XCTAssertNotNil(model.lastValidationError)
        XCTAssertTrue(model.panels.isEmpty)

        XCTAssertFalse(model.addPanel(label: "", rawURL: "https://panel.example.com", apiKey: "   "))
        XCTAssertEqual(model.lastValidationError, String(localized: "The API key is empty."))
        XCTAssertTrue(model.panels.isEmpty)
    }

    func testAddPanelRejectsDuplicate() {
        let model = makeModel(store: InMemoryCredentialStore())
        XCTAssertTrue(model.addPanel(label: "A", rawURL: "https://panel.example.com", apiKey: "k1"))
        XCTAssertFalse(model.addPanel(label: "A", rawURL: "https://panel.example.com/", apiKey: "k2"))
        XCTAssertEqual(model.panels.count, 1)
    }

    // MARK: - 编辑（原来只能删了重加）

    func testUpdatePanelChangesLabelAndURL() {
        let store = InMemoryCredentialStore()
        let model = makeModel(store: store)
        XCTAssertTrue(model.addPanel(label: "旧名字", rawURL: "https://old.example.com", apiKey: "k1"))
        let id = model.panels[0].id

        XCTAssertTrue(model.updatePanel(id: id, label: "新名字", rawURL: "https://new.example.com", apiKey: ""))

        XCTAssertEqual(model.panels[0].id, id, "编辑不该换 id（Keychain 里的 key 按 id 存）")
        XCTAssertEqual(model.panels[0].label, "新名字")
        XCTAssertEqual(model.panels[0].url.absoluteString, "https://new.example.com")
        XCTAssertEqual(store.key(for: id), "k1", "Key 留空 = 不修改")
        XCTAssertEqual(store.panels().first?.label, "新名字", "改动要落盘")
        XCTAssertEqual(model.model(for: id)?.panel?.url.absoluteString, "https://new.example.com", "模型也要跟着换地址")
    }

    func testUpdatePanelRotatesKeyWhenProvided() {
        let store = InMemoryCredentialStore()
        let model = makeModel(store: store)
        XCTAssertTrue(model.addPanel(label: "A", rawURL: "https://panel.example.com", apiKey: "old-key"))
        let id = model.panels[0].id

        XCTAssertTrue(model.updatePanel(id: id, label: "A", rawURL: "https://panel.example.com", apiKey: " new-key "))

        XCTAssertEqual(store.key(for: id), "new-key")
    }

    func testUpdatePanelRejectsInvalidURL() {
        let model = makeModel(store: InMemoryCredentialStore())
        XCTAssertTrue(model.addPanel(label: "A", rawURL: "https://panel.example.com", apiKey: "k"))
        let id = model.panels[0].id

        XCTAssertFalse(model.updatePanel(id: id, label: "A", rawURL: "not a url", apiKey: ""))
        XCTAssertEqual(model.panels[0].url.absoluteString, "https://panel.example.com", "失败时不能改坏原配置")
    }

    // MARK: - 删除

    func testRemovePanelClearsStoreAndModel() {
        let store = InMemoryCredentialStore()
        let model = makeModel(store: store)
        XCTAssertTrue(model.addPanel(label: "A", rawURL: "https://panel.example.com", apiKey: "k"))
        let id = model.panels[0].id

        model.removePanel(id: id)

        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertNil(model.model(for: id))
        XCTAssertNil(store.key(for: id), "Keychain 里的 key 也要删")
        XCTAssertTrue(store.panels().isEmpty)
    }

    // MARK: - 测试连接

    func testVerifyConnectionReportsRoleAndInstanceCount() async {
        let user = MCSManagerCurrentUser(
            permission: MCSManagerRole.admin,
            instances: [
                MCSManagerInstance(
                    daemonID: "d1", instanceUUID: "i1", nickname: "服", status: .running,
                    address: nil, players: nil
                )
            ]
        )
        let model = makeModel(
            store: InMemoryCredentialStore(),
            currentUser: .success(user)
        )

        let result = await model.verifyConnection(rawURL: "panel.example.com", apiKey: "k", panelID: nil)

        XCTAssertEqual(result, .connected(role: .administrator, instanceCount: 1))
    }

    func testVerifyConnectionSurfacesPanelMessage() async {
        let model = makeModel(
            store: InMemoryCredentialStore(),
            currentUser: .failure(MCSManagerModelError.unauthorized(panelMessage: "密钥不正确"))
        )

        let result = await model.verifyConnection(rawURL: "https://panel.example.com", apiKey: "k", panelID: nil)

        guard case .failed(let message) = result else {
            return XCTFail("应该是连接失败：\(result)")
        }
        XCTAssertTrue(message.contains("密钥不正确"), "面板原话要透出来：\(message)")
    }

    /// 编辑面板时 Key 留空 → 用已保存的 key 去试连（不用重新粘一次）。
    func testVerifyConnectionUsesStoredKeyWhenFieldIsEmpty() async {
        let panel = MCSManagerPanel(label: "A", url: URL(string: "https://panel.example.com")!)
        let store = InMemoryCredentialStore(panels: [panel], keys: [panel.id: "stored-key"])
        let recorder = KeyRecorder()
        let model = makeModel(
            store: store,
            usedKeys: { key in recorder.record(key) }
        )

        _ = await model.verifyConnection(
            rawURL: "https://panel.example.com",
            apiKey: "",
            panelID: panel.id
        )

        XCTAssertEqual(recorder.keys, ["stored-key"])
    }
}

private final class KeyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func record(_ key: String) { lock.withLock { storage.append(key) } }
    var keys: [String] { lock.withLock { storage } }
}
