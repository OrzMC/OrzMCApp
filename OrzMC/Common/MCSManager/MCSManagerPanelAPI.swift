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
    let permission: Int
    let instances: [MCSManagerInstance]
}

protocol MCSManagerPanelAPI: Sendable {
    func currentUser(advancedInstances: Bool) async throws -> MCSManagerCurrentUser
    func daemons() async throws -> [MCSManagerDaemon]
    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage
}
