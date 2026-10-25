//
//  ExarotonServerModel+StatusCenter.swift
//  OrzMC
//
//  exaroton 与**供应商无关的状态中心**（`Sources/OrzMCRemoteHosting/RemoteStatusCenter.swift`）的接缝。
//
//  规则没变（见 `docs/remote-status-source.md`）：WS 推送与 HTTP 轮询都只能从
//  `publishStatus(_:for:source:)` 这一个入口写进来；界面统一读 `effectiveStatus(for:)`。
//  这里只做三件事：把 SDK 状态码换成归一化状态、把字符串 id 换成 `RemoteInstanceID`、
//  让 `@Observable` 的 `statusVersion` 跟着状态变化走。
//

import OrzMCRemoteHosting

// MARK: - 状态换算

extension ServerStatus {
    /// exaroton 状态码 → 供应商无关状态（保留原始状态码，界面仍能区分 LOADING/PREPARING…）。
    var remoteInstanceStatus: RemoteInstanceStatus {
        RemoteInstanceStatus(state: remoteHostingState, rawStatus: rawValue)
    }
}

extension RemoteInstanceStatus {
    /// 供应商无关状态 → exaroton 状态码。没有原始码（不该出现在 exaroton 侧）时退化成 `.UNKNOWN`。
    var serverStatus: ServerStatus {
        guard let rawStatus else { return .UNKNOWN }
        return ServerStatus(rawValue: rawStatus) ?? .UNKNOWN
    }
}

// MARK: - 模型接缝

extension ExarotonServerModel {

    /// 实例 id 的全局键（供应商 + 原始 id）。状态中心、订阅、将来的 Keychain 条目都用它。
    func instanceID(_ serverID: String) -> RemoteInstanceID {
        RemoteInstanceID(provider: .exaroton, rawValue: serverID)
    }

    /// 订阅状态变化（每个订阅者一条独立流）。
    func statusEvents() -> AsyncStream<RemoteStatusChange> {
        statusCenter.events()
    }

    /// **唯一**的状态入口：WS 推送、HTTP 轮询、调试注入都从这里进。
    ///
    /// - 只有状态**真的变化**时才递增 `statusVersion`（界面用它触发更新）；
    /// - 快照存在 `statusCenter`，界面用 `effectiveStatus(for:)` 读。
    func publishStatus(_ status: ServerStatus, for serverID: String, source: RemoteStatusSource) {
        let changed = statusCenter.publish(
            status.remoteInstanceStatus,
            for: instanceID(serverID),
            source: source
        )
        if changed { statusVersion &+= 1 }
    }

    /// 推送通道收到任何消息都算"它还活着"（包括 keep-alive），轮询据此决定要不要兜底。
    func noteWebSocketActivity() {
        statusCenter.noteWebSocketActivity()
    }

    /// 界面统一从这里取状态：优先用推送值，没有推送再退回 HTTP 快照。
    func effectiveStatus(for server: ExarotonServer) -> ServerStatus? {
        guard let id = server.id else { return server.serverStatus }
        return statusCenter.status(for: instanceID(id))?.serverStatus ?? server.serverStatus
    }

    /// 推送来的状态（`id → 状态`）。**计算属性**：唯一存放在 `statusCenter` 里，这里只是投影。
    ///
    /// 直接整体赋值 / 单键写入都走状态中心（例如调试钩子注入假状态），因此仍会发事件、
    /// 仍会递增 `statusVersion`——比原来"直接写字典"更符合"唯一来源"。
    var liveStatuses: [String: ServerStatus] {
        get {
            statusCenter.allStatuses.reduce(into: [:]) { result, entry in
                guard entry.key.provider == .exaroton else { return }
                result[entry.key.rawValue] = entry.value.serverStatus
            }
        }
        set {
            let ids = Set(newValue.keys.map { instanceID($0) })
            // 删掉不再出现的实例，避免旧状态留在快照里。
            for instance in statusCenter.allStatuses.keys
            where instance.provider == .exaroton && !ids.contains(instance) {
                statusCenter.forget(instance)
            }
            for (serverID, status) in newValue {
                publishStatus(status, for: serverID, source: .local)
            }
        }
    }

    /// 换账号 / 退出登录时清空远程状态（否则旧账号的状态会漂到新账号的列表上）。
    func resetRemoteStatus() {
        statusCenter.reset()
        statusVersion &+= 1
    }
}
