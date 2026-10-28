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
import OrzMCRemoteHosting

struct MCSManagerAPIClient: MCSManagerPanelAPI {

    let client: Client

    init(serverURL: URL, apiKey: String) {
        self.client = MCSMClient.make(serverURL: serverURL, apiKey: apiKey)
    }

    init(client: Client) {
        self.client = client
    }

    func currentUser(advancedInstances: Bool) async throws -> MCSManagerCurrentUser {
        let output = try await client.getCurrentUser(query: .init(advanced: advancedInstances))
        let response = try await Self.currentUser(from: output)
        // 面板有两种形状：`{…用户字段…}`（裸）与 `{status, data: {…用户字段…}}`（带外壳）。
        // 实测面板 10.x 是后者；只读顶层会得到 `permission = nil / instances = 空`。
        let payload = response.data
        return MCSManagerCurrentUser(
            permission: payload?.permission ?? response.permission,
            instances: (payload?.instances ?? response.instances ?? []).compactMap {
                Self.instance(from: $0)
            }
        )
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

    // MARK: - 控制台实时流（B1）

    func streamChannel(daemonID: String, instanceUUID: String) async throws -> MCSMStreamChannel? {
        let output = try await client.getStreamChannel(
            query: .init(daemonId: daemonID, uuid: instanceUUID)
        )
        switch output {
        case .ok(let ok):
            switch ok.body {
            case .json(let response):
                return MCSMStreamChannel(response)
            case .plainText(let body):
                // 面板有时把同一份 JSON 用 `text/plain` 送出来（协议中间件的老毛病）。
                let data = try await Data(collecting: body, upTo: 64 * 1024)
                return MCSMStreamChannel(text: String(decoding: data, as: UTF8.self))
            @unknown default:
                // 未文档化的响应（面板加了新的 content type）：当成服务端错误，别静默成功。
                throw MCSManagerModelError.server(0, panelMessage: nil)
            }
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await Self.channelErrorMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await Self.channelErrorMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await Self.panelMessage(from: payload.body))
        }
    }

    /// `stream_channel` 的错误体：既可能是 `ErrorResponse`，也可能是 `text/plain` 的 JSON 文本。
    /// 403 与 500 的 `Body` 是**两个不同的生成类型**，所以这里两个重载。
    static func channelErrorMessage(from body: Operations.getStreamChannel.Output.Forbidden.Body) async -> String? {
        switch body {
        case .json(let response):
            return panelMessage(from: response)
        case .plainText(let textBody):
            return await plainTextMessage(from: textBody)
        @unknown default:
            return nil
        }
    }

    static func channelErrorMessage(from body: Operations.getStreamChannel.Output.InternalServerError.Body) async -> String? {
        switch body {
        case .json(let response):
            return panelMessage(from: response)
        case .plainText(let textBody):
            return await plainTextMessage(from: textBody)
        @unknown default:
            return nil
        }
    }

    static func plainTextMessage(from body: HTTPBody) async -> String? {
        let data = (try? await Data(collecting: body, upTo: 64 * 1024)) ?? Data()
        if let response = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: data) {
            return panelMessage(from: response)
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - 动作 + 控制台（P2-7 第 5 步）

    func perform(_ action: RemoteServerAction, daemonID: String, instanceUUID: String) async throws {
        // 三个端点各有自己的 `Query` 类型（生成器不复用），参数一样但类型不通用。
        switch action {
        case .start:
            try await Self.unwrap(
                client.openInstance(query: .init(daemonId: daemonID, uuid: instanceUUID))
            )
        case .stop:
            try await Self.unwrap(
                client.stopInstance(query: .init(daemonId: daemonID, uuid: instanceUUID))
            )
        case .restart:
            try await Self.unwrap(
                client.restartInstance(query: .init(daemonId: daemonID, uuid: instanceUUID))
            )
        case .kill:
            try await Self.unwrap(
                client.killInstance(query: .init(daemonId: daemonID, uuid: instanceUUID))
            )
        }
    }

    func sendCommand(_ command: String, daemonID: String, instanceUUID: String) async throws {
        try await Self.unwrap(
            client.sendCommand(
                query: .init(daemonId: daemonID, uuid: instanceUUID, command: command)
            )
        )
    }

    func outputLog(daemonID: String, instanceUUID: String, tailSize: Int?) async throws -> String {
        let output = try await client.getOutputLog(
            query: .init(
                daemonId: daemonID,
                uuid: instanceUUID,
                size: tailSize.map(String.init)
            )
        )
        switch output {
        case .ok(let ok):
            let body = try ok.body.plainText
            // 面板返回日志尾部，可能比我们需要的多（`size` 是面板侧的截断，不一定生效）。
            // 读取上限**不能**等于"想要的字节数"：`Data(collecting:upTo:)` 超过上限会抛
            // 「contains more than the maximum allowed」（真机踩过，日志比 2KB 就挂）。
            // 面板的 `size` 参数只是它那边的截断，不保证生效 → 这里给足余量。
            let data = try await Data(collecting: body, upTo: Self.outputLogReadCap)
            let raw = String(decoding: data, as: UTF8.self)
            // 面板把**所有**响应都包了一层 `{status, data, time}`（连纯文本接口也一样），
            // 所以这里要 unwrap；外壳里 status 非 2xx 时抛错（面板会写「节点未连接」之类）。
            let text: String
            do {
                text = try MCSMResponseEnvelope.checkedText(raw)
            } catch let error as MCSMResponseError {
                throw MCSManagerModelError.server(error.status, panelMessage: error.message)
            }
            // 面板忽略 `size` 时本地再截一次尾部（控制台只需要最近的一段）。
            guard let limit = tailSize, text.utf8.count > limit else { return text }
            return String(text.suffix(limit))
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await Self.panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await Self.panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await Self.panelMessage(from: payload.body))
        }
    }

    /// 控制台读取上限（4 MB）：够覆盖任何合理的日志尾部，又不会因为"比 size 大"而报错。
    static let outputLogReadCap = 4 * 1024 * 1024

    // MARK: - 响应解包（HTTP 状态码 → 面板级错误，尽量带上面板自己的文案）

    static func daemons(from output: Operations.getDaemons.Output) async throws -> [Components.Schemas.Daemon] {
        switch output {
        case .ok(let ok):
            return try ok.body.json.data
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(
                statusCode,
                panelMessage: await panelMessage(from: payload.body)
            )
        }
    }

    static func currentUser(from output: Operations.getCurrentUser.Output) async throws -> Components.Schemas.CurrentUserResponse {
        switch output {
        case .ok(let ok):
            return try ok.body.json
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    static func page(from output: Operations.getInstances.Output) async throws -> Components.Schemas.InstancePage {
        switch output {
        case .ok(let ok):
            return try ok.body.json.data
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(
                statusCode,
                panelMessage: await panelMessage(from: payload.body)
            )
        }
    }

    /// 动作端点只关心"有没有被拒绝"：成功时面板也会回 200 + 回执（我们不读），
    /// 失败走 403 / 500 —— 面板会把"不是你的实例"/节点错误原话放进 `data`，要转述给用户。
    static func unwrap(_ output: Operations.openInstance.Output) async throws {
        switch output {
        case .ok:
            return
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    static func unwrap(_ output: Operations.stopInstance.Output) async throws {
        switch output {
        case .ok:
            return
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    static func unwrap(_ output: Operations.restartInstance.Output) async throws {
        switch output {
        case .ok:
            return
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    static func unwrap(_ output: Operations.killInstance.Output) async throws {
        switch output {
        case .ok:
            return
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    static func unwrap(_ output: Operations.sendCommand.Output) async throws {
        switch output {
        case .ok:
            return
        case .forbidden(let response):
            throw MCSManagerModelError.unauthorized(panelMessage: await panelMessage(from: response.body))
        case .internalServerError(let response):
            throw MCSManagerModelError.server(500, panelMessage: await panelMessage(from: response.body))
        case .undocumented(statusCode: let statusCode, let payload):
            throw MCSManagerModelError.server(statusCode, panelMessage: await panelMessage(from: payload.body))
        }
    }

    /// 面板的错误响应是 `{"status":403,"data":"密钥不正确","time":…}` —— 把 `data` 取出来。
    /// 空值/纯空白当作没有（交给界面用兜底文案）。
    static func panelMessage(from errorResponse: Components.Schemas.ErrorResponse?) -> String? {
        let text = errorResponse?.data?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    /// 原始 body（`text/plain` 或未文档化响应）：先当 JSON 解 `ErrorResponse`，
    /// 解不出来就把纯文本原样返回（面板有时直接回一句中文）。
    static func panelMessage(from body: HTTPBody?) async -> String? {
        guard let body,
              let data = try? await Data(collecting: body, upTo: 64 * 1024)
        else { return nil }
        if let response = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: data) {
            return panelMessage(from: response)
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }


    // MARK: - 错误响应体（同一份 schema 在三个操作里是不同的生成类型，只好逐个重载）

    static func panelMessage(from body: Operations.getDaemons.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getInstances.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getCurrentUser.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getDaemons.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getInstances.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getCurrentUser.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.openInstance.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.stopInstance.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.restartInstance.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.killInstance.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.killInstance.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.sendCommand.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.openInstance.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.stopInstance.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.restartInstance.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.sendCommand.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getOutputLog.Output.Forbidden.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    static func panelMessage(from body: Operations.getOutputLog.Output.InternalServerError.Body) async -> String? {
        await panelMessage(fromErrorBody: body)
    }

    /// 面板给的是 `application/json` 就取 `data`；给的是 `text/plain`（面板实际行为）
    /// 就把原始文本当 JSON 再解一次，解不出就当普通文本返回。
    static func panelMessage(fromErrorBody body: some Any) async -> String? {
        switch body {
        case let json as Components.Schemas.ErrorResponse:
            return panelMessage(from: json)
        case let httpBody as HTTPBody:
            return await panelMessage(from: httpBody)
        default:
            return nil
        }
    }

    // MARK: - 字段搬运

    /// `GET /api/auth?advanced=true` 里的一条实例（普通用户视角）。
    static func instance(from info: Components.Schemas.AdvancedInstanceInfo) -> MCSManagerInstance? {
        guard !info.instanceUuid.isEmpty, !info.daemonId.isEmpty else { return nil }
        let ping = info.info?.allocatedPorts?.first
        let nickname = info.nickname.flatMap { $0.isEmpty ? nil : $0 }
        return MCSManagerInstance(
            daemonID: info.daemonId,
            instanceUUID: info.instanceUuid,
            nickname: nickname ?? info.instanceUuid,
            status: MCSManagerInstanceState(rawValue: info.status ?? -1),
            // 普通用户视角没有 pingConfig，只有面板侧的分配端口（host 是端口号）。
            address: ping?.host,
            players: info.info.map {
                MCSManagerPlayers(current: $0.currentPlayers, max: $0.maxPlayers)
            }
        )
    }

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
