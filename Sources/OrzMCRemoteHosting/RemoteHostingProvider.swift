//
//  RemoteHostingProvider.swift
//  OrzMCRemoteHosting
//
//  P2-7 第 1 步：远程托管供应商的抽象层（维护者 2026-10-25 拍板）。
//
//  分层（自下而上）：
//    1. `ExarotonAPI` / `MCSMAPI` —— 各家 OpenAPI 生成的客户端，互不相识；
//    2. **本文件** —— 供应商无关的"实例 + 状态 + 动作"，界面与业务只认这一层；
//    3. app 侧适配器（`ExarotonHostingProvider` …）—— 把已有模型/客户端包成 provider。
//
//  铁律：抽象层**不反向依赖**任何 SDK（否则再加一家供应商就要改抽象层）。
//

/// 远程托管供应商。
///
/// `allCases` 的顺序就是界面分组顺序（`RemoteHostingGrouping` 依赖它）。
public enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case exaroton
    /// MCSManager（自建面板）。凭据是面板 URL + apikey，见 `docs/remote-hosting-providers.md`。
    case mcsmanager

    public var id: String { rawValue }
}

/// 实例的**全局**标识：供应商 + 该供应商内部的 ID。
///
/// 两家供应商的原始 ID 可能撞车（都是随机串 / 数字），所以不能只用 `rawValue` 做键：
/// 状态中心、订阅、Keychain 条目全部以这个类型为准。
public struct RemoteInstanceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let provider: ProviderKind
    public let rawValue: String

    public init(provider: ProviderKind, rawValue: String) {
        self.provider = provider
        self.rawValue = rawValue
    }

    /// `exaroton:ATMiLQGZ43vW2k3W`（仅用于日志/调试展示）。
    public var description: String {
        "\(provider.rawValue):\(rawValue)"
    }
}

/// 一条要在列表里显示的实例（供应商无关）。
public struct RemoteInstanceSummary: Equatable, Sendable, Identifiable {
    public let id: RemoteInstanceID
    public let name: String
    /// 玩家连接地址。供应商能给出多个时取**稳定**那个（exaroton：静态地址优先于动态地址）。
    public let address: String?
    public let state: RemoteServerState

    public init(
        id: RemoteInstanceID,
        name: String,
        address: String?,
        state: RemoteServerState
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.state = state
    }

    public init(
        provider: ProviderKind,
        rawID: String,
        name: String,
        address: String?,
        state: RemoteServerState
    ) {
        self.init(
            id: RemoteInstanceID(provider: provider, rawValue: rawID),
            name: name,
            address: address,
            state: state
        )
    }

    public var provider: ProviderKind { id.provider }
}

/// 一家供应商的适配器：列实例 + 执行动作。
///
/// 状态**不在这里推**：状态仍走唯一状态中心（`publishStatus` / `statusEvents()`，
/// 见 `docs/remote-status-source.md`），供应商只负责"喂数据"。这样"WS 安静 30 秒才轮询"
/// 的判据不用在每个供应商里重写一遍。
public protocol RemoteHostingProvider: Sendable {
    var kind: ProviderKind { get }
    func listInstances() async throws -> [RemoteInstanceSummary]
    func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws
}

/// 一家供应商在界面上的一个分组（**多供应商按供应商分组**，不做过滤）。
public struct RemoteHostingGroup: Identifiable, Equatable, Sendable {
    public let provider: ProviderKind
    public let instances: [RemoteInstanceSummary]

    public init(provider: ProviderKind, instances: [RemoteInstanceSummary]) {
        self.provider = provider
        self.instances = instances
    }

    public var id: ProviderKind { provider }
}

public enum RemoteHostingGrouping {

    /// 把多个供应商的实例合成界面分组。
    ///
    /// - 分组顺序固定为 `ProviderKind.allCases`（不随网络返回顺序抖动）；
    /// - 组内保持输入顺序（调用方决定排序，例如按名称）；
    /// - **同一个实例出现多次时只保留第一份**：多账号把同一面板/同一实例拉了两遍时，
    ///   `ForEach` 的 `Identifiable` 不允许重复 id（会渲染错行）。
    public static func groups(from instances: [RemoteInstanceSummary]) -> [RemoteHostingGroup] {
        var seen = Set<RemoteInstanceID>()
        var buckets: [ProviderKind: [RemoteInstanceSummary]] = [:]

        for instance in instances {
            guard seen.insert(instance.id).inserted else { continue }
            buckets[instance.provider, default: []].append(instance)
        }

        return ProviderKind.allCases.compactMap { provider in
            guard let instances = buckets[provider], !instances.isEmpty else { return nil }
            return RemoteHostingGroup(provider: provider, instances: instances)
        }
    }
}

public enum RemoteHostingError: Error, Equatable, Sendable {
    /// 把 A 家的实例交给了 B 家的适配器（编程错误，不该出现在正常流程里）。
    case wrongProvider(expected: ProviderKind, actual: ProviderKind)
    /// 供应商没接受这个动作（请求失败 / 被拒绝）。调用方决定怎么提示用户。
    case actionFailed(RemoteServerAction)
    /// 这个供应商还没提供该动作（例如只读接入阶段）。调用方应把按钮置灰而不是假装成功。
    case actionNotSupported(RemoteServerAction)
}

/// 用两个闭包把已有实现包成 `RemoteHostingProvider`。
///
/// 为什么需要它：app 里的 `ExarotonServerModel` 是 `@MainActor @Observable`，
/// 还带着 Keychain / 通知 / 调试钩子，整体搬进这个包没有收益；但抽象层又不能 `import ExarotonAPI`
/// （否则第二家供应商进来就要改抽象层）。闭包适配器就是这两者之间的缝。
public struct ClosureRemoteHostingProvider: RemoteHostingProvider {
    public let kind: ProviderKind

    private let list: @Sendable () async throws -> [RemoteInstanceSummary]
    private let performAction: @Sendable (RemoteServerAction, RemoteInstanceID) async throws -> Void

    public init(
        kind: ProviderKind,
        list: @escaping @Sendable () async throws -> [RemoteInstanceSummary],
        perform: @escaping @Sendable (RemoteServerAction, RemoteInstanceID) async throws -> Void
    ) {
        self.kind = kind
        self.list = list
        self.performAction = perform
    }

    public func listInstances() async throws -> [RemoteInstanceSummary] {
        try await list()
    }

    public func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws {
        guard instance.provider == kind else {
            throw RemoteHostingError.wrongProvider(expected: kind, actual: instance.provider)
        }
        try await performAction(action, instance)
    }
}
