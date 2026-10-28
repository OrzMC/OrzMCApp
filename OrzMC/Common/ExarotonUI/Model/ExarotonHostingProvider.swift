//
//  ExarotonHostingProvider.swift
//  OrzMC
//
//  P2-7 第 1 步：把 exaroton 模型挂到供应商抽象层（`OrzMCRemoteHosting`）上。
//  只做映射，**不改变任何现有行为**、不加新界面 —— 界面仍然走原来的 `servers` / `effectiveStatus`。
//

import OrzMCRemoteHosting

/// `ExarotonServerModel` 的供应商适配器。
///
/// 抽象层（`RemoteHostingProvider`）不能 `import ExarotonAPI`，所以"怎么调 exaroton"
/// 只能留在 app 这一侧；将来 MCSM 走同一个协议，界面就不必知道下面是谁。
@MainActor
struct ExarotonHostingProvider: RemoteHostingProvider {

    /// 供应商是常量：`nonisolated` 才能满足协议的同步要求（不碰 MainActor 状态）。
    nonisolated var kind: ProviderKind { .exaroton }

    /// 强引用模型：提供商由模型**按需**创建（`model.hostingProvider`），模型不持有提供商，不成环。
    let model: ExarotonServerModel

    func listInstances() async throws -> [RemoteInstanceSummary] {
        model.instanceSummaries()
    }

    func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws {
        guard instance.provider == kind else {
            throw RemoteHostingError.wrongProvider(expected: kind, actual: instance.provider)
        }

        // exaroton 没有"强杀"这个操作（它只有 start/stop/restart，服务器由平台托管）——
        // 明确拒绝，别静默退化成 stop（那会让界面以为强杀成功了）。
        guard action != .kill else {
            throw RemoteHostingError.actionNotSupported(action)
        }

        let accepted: Bool
        switch action {
        case .start:
            accepted = await model.startServer(serverId: instance.rawValue)
        case .stop:
            accepted = await model.stopServer(serverId: instance.rawValue)
        case .restart:
            accepted = await model.restartServer(serverId: instance.rawValue)
        case .kill:
            throw RemoteHostingError.actionNotSupported(action)
        }

        // 失败原因模型已经写进 `actionErrors`（界面在动作旁展示、可重试）。
        // 这里只把"请求没被接受"这个事实告诉抽象层的调用方，免得它以为提交成功。
        guard accepted else { throw RemoteHostingError.actionFailed(action) }
    }
}

extension ExarotonServerModel {

    /// 当前账号的供应商适配器（每次取都是新值，无状态）。
    var hostingProvider: any RemoteHostingProvider {
        ExarotonHostingProvider(model: self)
    }

    /// 把 `servers` 映射成供应商无关的摘要。
    ///
    /// 状态取**唯一来源** `effectiveStatus(for:)`（WS 推送优先、HTTP 快照兜底），
    /// 不要直接读 `server.serverStatus` —— 那会让列表和详情又对不上（见 `docs/remote-status-source.md`）。
    func instanceSummaries() -> [RemoteInstanceSummary] {
        servers.compactMap { server in
            guard let id = server.id else { return nil }
            return RemoteInstanceSummary(
                provider: .exaroton,
                rawID: id,
                name: server.name ?? String(localized: "Server"),
                // 静态地址是账号里配的那条，动态地址每次启动会变 → 摘要里优先给稳定的那个。
                address: server.staticAddress ?? server.dynamicAddress,
                state: effectiveStatus(for: server)?.remoteHostingState ?? .unknown
            )
        }
    }
}
