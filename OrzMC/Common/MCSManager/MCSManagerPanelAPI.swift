//
//  MCSManagerPanelAPI.swift
//  OrzMC
//
//  app 内部的**只读面板接口**：模型只依赖它。
//
//  为什么再抽一层（MCSMAPI 已经是一个干净的生成客户端了）：
//    - 生成的类型来自 OpenAPI（`Client` / `Components.Schemas.*`），单测要碰它就得把
//      OpenAPI 运行时一起拉进测试目标；
//    - 这一层只描述"面板能给我们什么"，测试用假实现就能覆盖分页/错误/映射，
//      `MCSManagerAPIClient` 只做"生成类型 → 这个接口"的字段搬运。
//

import Foundation

import MCSMAPI
import OrzMCRemoteHosting

/// 面板上的一个节点（Daemon）。
struct MCSManagerDaemon: Equatable, Sendable {
    let uuid: String
    /// 面板认为这个节点是否连通（掉线的节点不要去问实例）。
    let available: Bool
}

/// 一页实例。
struct MCSManagerInstancePage: Equatable, Sendable {
    let instances: [MCSManagerInstance]
    /// 面板给出的总页数（nil = 不认识/只有一页）。
    let maxPage: Int?
}

/// 面板账号角色（面板源码 `ROLE`）。普通 key 用不了管理员端点，界面/模型据此选入口。
enum MCSManagerRole {
    static let guest = 0
    static let user = 1
    static let admin = 10
}

/// 当前登录用户（面板 `GET /api/auth`）。
///
/// `permission`：0 guest / 1 user / 10 admin。**普通用户的 key 用不了管理员端点**，
/// 必须走 `GET /api/auth?advanced=true` 列"自己的"实例；管理员则要按节点列全部实例。
struct MCSManagerCurrentUser: Equatable, Sendable {
    /// 面板没返回时就当"不知道"，由模型去试管理员端点再回退（老版本面板可能不返回）。
    let permission: Int?
    let instances: [MCSManagerInstance]
}

protocol MCSManagerPanelAPI: Sendable {
    func currentUser(advancedInstances: Bool) async throws -> MCSManagerCurrentUser
    func daemons() async throws -> [MCSManagerDaemon]
    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage

    // MARK: - 动作 + 控制台（P2-7 第 5 步）

    /// 生命周期动作。面板中间件先校验"这台实例是不是你的"（`daemonID` + `instanceUUID` 缺一不可），
    /// 所以普通用户的 key 也能用，不需要管理员。
    func perform(_ action: RemoteServerAction, daemonID: String, instanceUUID: String) async throws

    /// 往控制台发一条命令（`/` 开头是 MC 命令，不带 `/` 是控制台命令）。
    func sendCommand(_ command: String, daemonID: String, instanceUUID: String) async throws

    /// 控制台的**日志尾部**（面板返回纯文本，可能从半行开始）。
    /// - Parameter tailSize: 只取末尾多少字节（`nil` = 面板默认，可能很大）。
    func outputLog(daemonID: String, instanceUUID: String, tailSize: Int?) async throws -> String

    /// 控制台**实时流**通道（`POST /api/protected_instance/stream_channel`）。
    ///
    /// 返回 `nil` 表示面板给不出通道信息（版本太老 / 字段缺失）——调用方回退轮询。
    /// 拿到之后还要去连 `addr` 上的 socket.io；连不上（节点在 NAT 后面）同样回退轮询。
    func streamChannel(daemonID: String, instanceUUID: String) async throws -> MCSMStreamChannel?
}
