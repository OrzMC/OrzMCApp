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
        defer { isLoadingList = false }
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
    private func performLifecycleAction<Output, OK>(
        serverId: String,
        requesting: String,
        accepted: String,
        failed: String,
        call: (Client) async throws -> Output,
        okCase: (Output) -> OK?,
        success: (OK) throws -> Bool?
    ) async -> Bool {
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
            failAction(serverId, failed, detail: error.localizedDescription)
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
            errorMessage = "Failed to fetch credit pool info: \(error.localizedDescription)"
            return (nil, nil, nil)
        }
    }

    // MARK: - 内存

    func getRAM(serverId: String) async -> Int32? {
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
                detail: error.localizedDescription
            )
            return nil
        }
    }

    func changeRAM(serverId: String, ramGB: Int32) async -> Int32? {
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
            failMemory(serverId, detail: error.localizedDescription)
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
