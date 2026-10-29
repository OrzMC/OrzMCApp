//
//  ExarotonServerModel.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import ExarotonHTTP
import ExarotonWebSocket
import OpenAPIRuntime
import OpenAPIURLSession
import Security
import OrzMCRemoteHosting
import SwiftUI

/// HTTP 客户端构造期的错误（不依赖网络）。
enum ExarotonClientError: Error {
    /// `Servers.Server1.url()` 失败（配置/代码问题，而非网络问题）。
    case invalidServerURL
}

@MainActor
@Observable
final class ExarotonServerModel {

    @ObservationIgnored private let accountToken: String?

    init(accountToken: String? = nil) {
        self.accountToken = accountToken
    }

    var path = NavigationPath()

    static let accountTokenPersistentKey = "EXAROTON_TOKEN"

    @ObservationIgnored
    var token: String {
        get {
            if let accountToken { return accountToken }
            #if DEBUG
            // UI 测试 / 截图验收：`ORZMC_DEMO_TOKEN` 直接注入账号 Token，不写 Keychain。
            // 真机与模拟器都能用；模拟器上没法手动登录，这是跑"真实账号"用例的唯一路径。
            // 值只放在本地 secret 文件里（见 scripts/dev/uitest-secrets.example.env），不进仓库。
            if let demo = ProcessInfo.processInfo.environment["ORZMC_DEMO_TOKEN"], !demo.isEmpty {
                return demo
            }
            #endif
            if let token = KeychainTokenStore.load(key: Self.accountTokenPersistentKey) {
                return token
            }
            let legacyToken = UserDefaults.standard.string(forKey: Self.accountTokenPersistentKey) ?? ""
            if !legacyToken.isEmpty {
                try? KeychainTokenStore.save(legacyToken, key: Self.accountTokenPersistentKey)
                UserDefaults.standard.removeObject(forKey: Self.accountTokenPersistentKey)
            }
            return legacyToken
        }
        set {
            guard accountToken == nil else { return }
            let trimmedToken = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedToken.isEmpty {
                try? KeychainTokenStore.delete(key: Self.accountTokenPersistentKey)
                UserDefaults.standard.removeObject(forKey: Self.accountTokenPersistentKey)
            } else {
                try? KeychainTokenStore.save(trimmedToken, key: Self.accountTokenPersistentKey)
            }
        }
    }


    // HTTP Client
    /// 构造 HTTP 客户端。
    ///
    /// 注意：这里**不再**是有副作用的 getter（旧实现会在 URL 构造失败时直接写 `errorMessage`，
    /// 于是任何一次读取都可能触发视图更新）。需要统一报错时用 `clientOrReportError()`。
    func makeClient() throws -> Client {
        guard let serverURL = try? Servers.Server1.url() else {
            throw ExarotonClientError.invalidServerURL
        }
        return Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [AuthenticationMiddleware(token: token)]
        )
    }

    /// 取客户端；不可用时把原因写进 `errorMessage` 并返回 nil。
    func clientOrReportError() -> Client? {
        do {
            return try makeClient()
        } catch {
            errorMessage = String(localized: "Exaroton server URL is invalid.")
            return nil
        }
    }

    var servers = [ExarotonServer]()

    /// 后台状态轮询的 Task（见 `ExarotonServerModel+Refresh.swift`）。
    /// 挂在模型上而不是视图上：切换页面/退出详情都不会中断。
    @ObservationIgnored
    var backgroundRefreshTask: Task<Void, Never>?

    /// App 是否在前台（由场景驱动）。后台时不轮询。
    @ObservationIgnored
    var isSceneActive = true

    // MARK: - 状态中心（唯一来源，见 ExarotonServerModel+StatusCenter.swift）

    /// 供应商无关的状态中心（实现在 `Sources/OrzMCRemoteHosting`）。
    /// 一个账号一份：WS 活的/刷新节律都是账号级的，多账号互不干扰。
    @ObservationIgnored
    let statusCenter = RemoteStatusCenter()
    var creditPools = [ExarotonCreditPool]()
    var errorMessage: String?
    var isLoadingList = false
    var listLoadError: String?
    var hasLoadedList = false
    var savedMemory: [String: Int32] = [:]
    var memoryRevision: [String: Int] = [:]
    /// 实例级在途互斥（生命周期动作与内存变更互相排除，见 `RemoteActionGate`）。
    var gate = RemoteActionGate()
    /// 请求已经提交（非模态、不要求确认）；错误单独存放，便于在动作旁展示重试。
    var actionMessages: [String: String] = [:]
    var actionErrors: [String: String] = [:]
    /// 内存保存失败（草稿保留、确认值不变 → UI 仍显示未保存）。
    var memoryErrors: [String: String] = [:]
    /// 内存读取失败（此时没有可编辑的草稿，需要重试入口）。
    var memoryLoadErrors: [String: String] = [:]
    // WebSocket Client
    @ObservationIgnored
    var websocket: ExarotonWebSocketAPI?
    @ObservationIgnored
    var websocketServerID: String?
    /// 强引用回调转发器：`ExarotonWebSocketAPI.delegate` 是 weak，而转发器要活到连接结束。
    @ObservationIgnored
    var socketDelegate: ExarotonSocketDelegate?
    /// 连接代数：丢弃上一条连接迟到的回调（见 `ConnectionEpoch`）。
    @ObservationIgnored
    var connectionEpoch = ConnectionEpoch()

    var readyServerID: String?

    /// 是否**真的可用**：SDK 里 `onConnected` 并不总会被调用（实测真机：`onReady` 已拿到
    /// `readyServerID`，`isConnected` 仍是 false）。只认 `isConnected` 会导致
    /// "握手成功但不订阅流、控制台一直空/一直提示未连接"。
    var isLive: Bool {
        #if DEBUG
        // 界面验收用：`ORZMC_DEMO_FAKE_LIVE=1` 假装已握手，便于在没有真实在线服务器时
        // 截取"控制台有日志"的界面（也用于 UI 测试断言控制台区块）。
        if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_LIVE"] == "1" { return true }
        #endif
        return isConnected || readyServerID != nil
    }
    var isConnected: Bool = false
    var disconnectedReason: String?
    var statusChangedServer: ExarotonWebSocket.Server?
    /// 状态推送的版本号：视图用 `.onChange(of:)` 响应，
    /// 而不是 `Optional.publisher`（那个只在订阅那一刻发一次，靠 body 重算才「碰巧」更新）。
    /// 递增时机：状态中心里的状态**真的变化**时（`publishStatus`）或连接复位时（`reset`）。
    var statusVersion = 0
    /// 已订阅的远程流（由 `onStreamStarted` / `onStreamStopped` 回执维护）。
    var activeStreams: Set<StreamCategory> = []
    var streamStarted: ExarotonWebSocket.StreamCategory?
    var streamStopped: ExarotonWebSocket.StreamCategory?

    /// 除 `status` 外需要按需订阅的流（`status` 连接后默认就有）。
    static let streamCategories = StreamCategory.allCases.filter { $0 != .status }
    var consoleLine: String?
    private var consoleBuffer = RemoteConsoleBuffer()
    var consoleLines: [RemoteConsoleBuffer.Line] { consoleBuffer.lines }

    func appendConsoleLine(_ text: String) { consoleBuffer.append(text) }
    func clearConsole() { consoleBuffer.clear() }
    var tickChanged: ExarotonWebSocket.Tick?
    var statsChanged: ExarotonWebSocket.Stats?
    var heapChanged: ExarotonWebSocket.Heap?
}

enum KeychainTokenStore {
    enum KeychainError: Error {
        case unhandledStatus(OSStatus)
    }

    static func load(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, key: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery(key: key)
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func delete(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "OrzMC",
            kSecAttrAccount as String: key
        ]
    }
}
