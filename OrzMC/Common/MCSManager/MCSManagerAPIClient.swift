//
//  MCSManagerAPIClient.swift
//  OrzMC
//
//  `MCSManagerPanelAPI` 的真实实现：把 `MCSMAPI`（OpenAPI 生成）的调用与类型收敛在这里。
//  新增端点 / 面板字段变化都只改这个文件，模型与界面不受影响。
//

import Foundation
import MCSMAPI
import OpenAPIRuntime

struct MCSManagerAPIClient: MCSManagerPanelAPI {

    let client: Client

    init(serverURL: URL, apiKey: String) {
        self.client = MCSMClient.make(serverURL: serverURL, apiKey: apiKey)
    }

    init(client: Client) {
        self.client = client
    }

    func daemons() async throws -> [MCSManagerDaemon] {
        let output = try await client.getDaemons()
        return try await Self.daemons(from: output).map { daemon in
            MCSManagerDaemon(uuid: daemon.uuid, available: daemon.available ?? true)
        }
    }

    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage {
        let output = try await client.getInstances(
            query: .init(daemonId: daemonID, page: page, page_size: pageSize)
        )
        let body = try await Self.page(from: output)
        return MCSManagerInstancePage(
            instances: body.data.compactMap { Self.instance(daemonID: daemonID, detail: $0) },
            maxPage: body.maxPage
        )
    }

    // MARK: - 响应解包（HTTP 状态码 → 面板级错误，尽量带上面板自己的文案）

    static func daemons(from output: Operations.getDaemons.Output) async throws -> [Components.Schemas.Daemon] {
        switch output {
        case .ok(let ok):
            return try ok.body.json.data
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(
                panelMessage: panelMessage(from: try? response.body.json)
            )
        case .internalServerError(let response):
            throw MCSManagerModelError.server(
                500,
                panelMessage: panelMessage(from: try? response.body.json)
            )
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(
                statusCode,
                panelMessage: await panelMessage(from: payload.body)
            )
        }
    }

    static func page(from output: Operations.getInstances.Output) async throws -> Components.Schemas.InstancePage {
        switch output {
        case .ok(let ok):
            return try ok.body.json.data
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(
                panelMessage: panelMessage(from: try? response.body.json)
            )
        case .internalServerError(let response):
            throw MCSManagerModelError.server(
                500,
                panelMessage: panelMessage(from: try? response.body.json)
            )
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(
                statusCode,
                panelMessage: await panelMessage(from: payload.body)
            )
        }
    }

    /// 面板的错误响应是 `{"status":403,"data":"密钥不正确","time":…}` —— 把 `data` 取出来。
    /// 空值/纯空白当作没有（交给界面用兜底文案）。
    static func panelMessage(from errorResponse: Components.Schemas.ErrorResponse?) -> String? {
        let text = errorResponse?.data?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    /// 无文档响应（状态码不在 spec 里）只能自己解 body。
    static func panelMessage(from body: HTTPBody?) async -> String? {
        guard let body,
              let data = try? await Data(collecting: body, upTo: 64 * 1024),
              let response = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: data)
        else { return nil }
        return panelMessage(from: response)
    }

    // MARK: - 字段搬运

    static func instance(daemonID: String, detail: Components.Schemas.InstanceDetail) -> MCSManagerInstance? {
        // 没有 id 就没法做键（状态中心/动作都要它）→ 跳过，而不是造一个假 id。
        guard !detail.instanceUuid.isEmpty else { return nil }

        let ping = detail.config?.pingConfig
        let address: String? = {
            guard let ip = ping?.ip, !ip.isEmpty else { return nil }
            guard let port = ping?.port else { return ip }
            return "\(ip):\(port)"
        }()
        let nickname = detail.config?.nickname.flatMap { $0.isEmpty ? nil : $0 }

        return MCSManagerInstance(
            daemonID: daemonID,
            instanceUUID: detail.instanceUuid,
            nickname: nickname ?? detail.instanceUuid,
            status: MCSManagerInstanceState(rawValue: detail.status),
            address: address,
            players: detail.info.map {
                MCSManagerPlayers(current: $0.currentPlayers, max: $0.maxPlayers)
            }
        )
    }
}
