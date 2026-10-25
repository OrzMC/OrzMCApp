//
//  ExarotonServerModel+HTTP.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import ExarotonHTTP
import Foundation

extension ExarotonServerModel {
    func reloadList() async {
        guard !isLoadingList, !token.isEmpty, let httpClient = clientOrReportError() else { return }
        let requestedToken = token
        isLoadingList = true
        listLoadError = nil
        refreshStartedAt = Date()
        defer {
            isLoadingList = false
            lastRefreshFinished = Date()
        }
        do {
            async let serversResponse = httpClient.getServers()
            async let poolsResponse = httpClient.getCreditPools()
            let responses = try await (serversResponse, poolsResponse)
            guard token == requestedToken, !Task.isCancelled else { return }
            switch responses {
            case (.ok(let serverOK), .ok(let poolOK)):
                let serverData = try serverOK.body.json
                let poolData = try poolOK.body.json
                guard serverData.success == true, poolData.success == true else {
                    listLoadError = String(localized: "Could not load remote servers. Check your account token and try again.")
                    return
                }
                servers = serverData.data ?? []
                creditPools = poolData.data ?? []
                hasLoadedList = true
                // 轮询结果也走同一个状态入口：业务侧只看事件，不用管数据从哪来。
                for server in servers {
                    guard let id = server.id, let status = server.serverStatus else { continue }
                    publishStatus(status, for: id, source: .polling)
                }
            default:
                listLoadError = String(localized: "Could not load remote servers. Check your account token and try again.")
            }
        } catch {
            guard token == requestedToken, !Task.isCancelled else { return }
            listLoadError = String(localized: "Could not load remote servers. Check your connection and try again.")
        }
    }

    // MARK: - 生命周期动作
    //
    // 三条硬规则（2026-10-22 交互审查 §2）：
    // 1. 在**首次 await 之前**占用实例（`gate`），重复点击/并发 Task 直接放弃，不依赖按钮 disabled；
    // 2. 只承诺「请求已提交」，真实运行状态等服务端后续状态推送确认；
    // 3. 失败不弹必须确认的全局框：错误留在动作旁（`actionErrors`），请求结束即释放互斥，按钮可重试。

    func startServer(serverId: String) async -> Bool {
        await performLifecycleAction(
            serverId: serverId,
            requesting: String(localized: "Requesting server start…"),
            accepted: String(localized: "Server start requested."),
            failed: String(localized: "Could not request the server to start."),
            call: { try await $0.getStartServer(path: .init(serverId: serverId)) },
            okCase: { if case .ok(let ok) = $0 { return ok } else { return nil } },
            success: { try $0.body.json.success }
        )
    }

    func stopServer(serverId: String) async -> Bool {
        await performLifecycleAction(
            serverId: serverId,
            requesting: String(localized: "Requesting server stop…"),
            accepted: String(localized: "Server stop requested."),
            failed: String(localized: "Could not request the server to stop."),
            call: { try await $0.stopServer(path: .init(serverId: serverId)) },
            okCase: { if case .ok(let ok) = $0 { return ok } else { return nil } },
            success: { try $0.body.json.success }
        )
    }

    func restartServer(serverId: String) async -> Bool {
        await performLifecycleAction(
            serverId: serverId,
            requesting: String(localized: "Requesting server restart…"),
            accepted: String(localized: "Server restart requested."),
            failed: String(localized: "Could not request the server to restart."),
            call: { try await $0.restartServer(path: .init(serverId: serverId)) },
            okCase: { if case .ok(let ok) = $0 { return ok } else { return nil } },
            success: { try $0.body.json.success }
        )
    }

    /// 三个生命周期端点共用同一套「占用 → 请求 → 判定 → 释放」，避免三份实现漂移。
    #if DEBUG
    /// 记录生命周期请求（谁在什么时候发的），供诊断钩子导出。
    /// 起因：用户反馈"进详情页就自动启动了服务器"，光看 UI 无法判断是不是 App 发的请求。
    static var debugActionLog: [String] = []
    #endif

    private func performLifecycleAction<Output, OK>(
        serverId: String,
        requesting: String,
        accepted: String,
        failed: String,
        call: (Client) async throws -> Output,
        okCase: (Output) -> OK?,
        success: (OK) throws -> Bool?
    ) async -> Bool {
        #if DEBUG
        let stamp = Date().formatted(date: .omitted, time: .standard)
        Self.debugActionLog.append("\(stamp) request server=\(serverId) msg=\(requesting)")
        #endif
        guard let httpClient = clientOrReportError() else { return false }
        guard gate.beginAction(serverID: serverId) else { return false }
        actionMessages[serverId] = requesting
        actionErrors[serverId] = nil
        defer { gate.endAction(serverID: serverId) }

        do {
            let output = try await call(httpClient)
            guard let ok = okCase(output) else {
                failAction(serverId, failed, detail: String(localized: "The service returned an unexpected response."))
                return false
            }
            guard try success(ok) == true else {
                failAction(serverId, failed, detail: String(localized: "The service did not accept the request."))
                return false
            }
            actionMessages[serverId] = accepted
            return true
        } catch {
            // 取消（页面消失 / 换代）不当作错误：`describe` 返回 nil 时只保留主句。
            failAction(serverId, failed, detail: RemoteHostingErrorText.describe(error))
            return false
        }
    }

    func fetchCreditPoolInfo(_ pool: ExarotonCreditPool) async -> (ExarotonCreditPool?, [ExarotonCreditMember]?, [ExarotonServer]?)? {
        guard let poolId = pool.id
        else {
            return nil
        }
        guard let httpClient = clientOrReportError() else {
            return nil
        }
        do {
            async let poolResponse = try await httpClient.getCreditPool(path: .init(poolId: poolId))
            async let membersResponse = try await httpClient.getCreditPoolMembers(path: .init(poolId: poolId))
            async let serversResponse = try await httpClient.getCreditPoolServers(path: .init(poolId: poolId))
            switch (try await poolResponse, try await membersResponse, try await serversResponse) {
            case (.ok(let poolOk), .ok(let membersOk), .ok(let serversOk)):
                let pool = try poolOk.body.json.data
                let members = try membersOk.body.json.data
                let servers = try serversOk.body.json.data
                return (pool, members, servers)
            default:
                return (nil, nil, nil)
            }
        } catch let error {
            // 曾经把原始 `NSError` 直接拼进弹窗正文（真机反馈：取消也弹「远程服务器错误」）。
            // 现在只给一句人话；取消（`nil`）干脆不打断用户。
            errorMessage = RemoteHostingErrorText.describe(error)
            return (nil, nil, nil)
        }
    }

    // MARK: - 内存

    func getRAM(serverId: String) async -> Int32? {
        #if DEBUG
        // 界面验收用的假服务器没有真实 HTTP 客户端，直接给一个可用值，
        // 否则演示详情页永远挂着「无法读取服务器内存大小」。
        if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_SERVER"] == "1" {
            savedMemory[serverId] = 4
            memoryLoadErrors[serverId] = nil
            return 4
        }
        #endif
        // 内存变更在途时不要把服务端的旧值读回来覆盖。
        if gate.pendingMemoryChanges.contains(serverId) { return savedMemory[serverId] }
        let revision = memoryRevision[serverId, default: 0]
        guard let httpClient = clientOrReportError() else { return nil }
        do {
            let response = try await httpClient.getServerRam(path: .init(serverId: serverId))
            switch response {
            case .ok(let ok):
                let data = try ok.body.json.data
                guard memoryRevision[serverId, default: 0] == revision else { return savedMemory[serverId] }
                memoryLoadErrors[serverId] = nil
                if let ram = data?.ram { savedMemory[serverId] = ram }
                return data?.ram
            default:
                memoryLoadErrors[serverId] = Self.failureText(
                    String(localized: "Could not load server memory."),
                    detail: String(localized: "The service returned an unexpected response.")
                )
                return nil
            }
        } catch {
            memoryLoadErrors[serverId] = Self.failureText(
                String(localized: "Could not load server memory."),
                detail: RemoteHostingErrorText.describe(error)
            )
            return nil
        }
    }

    func changeRAM(serverId: String, ramGB: Int32) async -> Int32? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_SERVER"] == "1" {
            savedMemory[serverId] = ramGB
            memoryErrors[serverId] = nil
            return ramGB
        }
        #endif
        guard let httpClient = clientOrReportError() else { return nil }
        guard gate.beginMemoryChange(serverID: serverId) else { return nil }
        memoryRevision[serverId, default: 0] += 1
        memoryErrors[serverId] = nil
        defer { gate.endMemoryChange(serverID: serverId) }
        do {
            let response = try await httpClient.postServerRam(path: .init(serverId: serverId), body: .json(.init(ram: ramGB)))
            switch response {
            case .ok(let ok):
                let data = try ok.body.json.data
                guard let ram = data?.ram else {
                    failMemory(serverId, detail: String(localized: "The service returned an unexpected response."))
                    return nil
                }
                memoryLoadErrors[serverId] = nil
                savedMemory[serverId] = ram
                return ram
            default:
                failMemory(serverId, detail: String(localized: "The service returned an unexpected response."))
                return nil
            }
        } catch {
            failMemory(serverId, detail: RemoteHostingErrorText.describe(error))
            return nil
        }
    }

    // MARK: - 反馈文案

    /// 请求失败：清掉「正在请求…」、把错误留在动作旁（`actionErrors`），不弹全局对话框。
    private func failAction(_ serverId: String, _ message: String, detail: String? = nil) {
        actionMessages[serverId] = nil
        actionErrors[serverId] = Self.failureText(message, detail: detail)
    }

    /// 内存保存失败：草稿保留、确认值不变（UI 仍显示「未保存」），错误就地展示。
    private func failMemory(_ serverId: String, detail: String? = nil) {
        memoryErrors[serverId] = Self.failureText(
            String(localized: "Could not save server memory. Try again."),
            detail: detail
        )
    }

    /// 本地化主句 + 系统错误细节：主句保证可读，细节保留排查信息。
    ///
    /// 细节本身是完整句子（本地化文案自带句号），直接塞进括号会变成
    /// 「…（服务返回了非预期响应。）」这种双标点，所以先去掉尾部句号。
    static func failureText(_ message: String, detail: String? = nil) -> String {
        guard let detail, !detail.isEmpty else { return message }
        let cleaned = detail.trimmingCharacters(in: CharacterSet(charactersIn: "。."))
        return "\(message) (\(cleaned))"
    }
}
