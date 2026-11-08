//
//  CloudRecords.swift
//  OrzMC
//
//  **整条记录**（配置 + 凭据）的 iCloud 同步。
//
//  为什么需要它（2026-11-08 维护者实测反馈"设为 iCloud 后两端不同步"）：
//  之前的实现只把**凭据**放进了同步钥匙串，而"这台服务器叫什么、地址是什么、档位是什么"
//  仍然只存在各自的 UserDefaults 里 —— 另一台设备根本不知道有这条记录，自然不会去 iCloud 找。
//  设计文档一开始写的就是"配置和凭据一起保存到 iCloud 钥匙串"，这里补上配置那一半。
//
//  约定：
//   · 只有 `storageMode == .iCloud` 的记录才会进云端（其余档位留在本机，别人看不到）；
//   · 云端记录 = `{kind, config(JSON), secret}`，写进同步钥匙串（访问组见 P4）；
//   · 拉取时按 id 合并：云端有的更新到本机（档位置为 `.iCloud`）；
//     本机标了 `.iCloud` 但云端没有的 → 删除（这样"在一端删掉"才能传播到另一端）；
//   · 合并失败只影响同步，不影响本机已有数据。
//

import Foundation
import OrzMCFoundation

enum CloudRecordKind: String, Codable, CaseIterable {
    case selfHosted
    case exaroton
    case mcsm
}

/// 云端记录的内容：配置（明文 JSON）+ 凭据。
struct CloudRecordPayload: Codable {
    var kind: CloudRecordKind
    var config: Data
    var secret: String

    init(kind: CloudRecordKind, config: Data, secret: String) {
        self.kind = kind
        self.config = config
        self.secret = secret
    }
}

enum CloudRecords {

    /// 把一条记录推上云端（仅当它的档位是 `.iCloud`）。
    @discardableResult
    static func push(
        id: UUID,
        kind: CloudRecordKind,
        config: Data,
        secret: String
    ) -> Bool {
        guard ServerSecretsStore.isAvailable(.iCloud) else { return false }
        let payload = CloudRecordPayload(kind: kind, config: config, secret: secret)
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        let record = ServerStorageRecord(
            id: id,
            provider: "cloud.\(kind.rawValue)",
            payload: data
        )
        do {
            try ServerSecretsStore.writeCloudRecord(record)
            // 清掉旧格式（只含凭据、provider 是业务前缀）的同 id 记录，避免云端留两份。
            for legacy in legacyProviders(for: kind) {
                ServerSecretsStore.removeCloudRecord(id: id, provider: legacy)
            }
            return true
        } catch {
            return false
        }
    }

    /// 旧实现（P2）把"只有凭据"的记录直接写在业务 provider 下，这里给出对应前缀便于清理/兼容。
    static func legacyProviders(for kind: CloudRecordKind) -> [String] {
        switch kind {
        case .selfHosted: return ["selfhosted.rcon"]
        case .exaroton: return ["exaroton.account"]
        case .mcsm: return ["mcsm.panel"]
        }
    }

    /// 从云端删掉一条（切走 iCloud 档位或删除记录时调用）。
    static func remove(id: UUID, kind: CloudRecordKind) {
        ServerSecretsStore.removeCloudRecord(id: id, provider: "cloud.\(kind.rawValue)")
    }

    /// 读出云端所有记录（按 kind 分组）。
    static func pull() -> [CloudRecordKind: [(id: UUID, config: Data, secret: String)]] {
        var result: [CloudRecordKind: [(UUID, Data, String)]] = [:]
        for record in ServerSecretsStore.cloudRecords() {
            guard let kind = CloudRecordKind.allCases.first(where: { "cloud.\($0.rawValue)" == record.provider }),
                  let payload = try? JSONDecoder().decode(CloudRecordPayload.self, from: record.payload),
                  payload.kind == kind
            else { continue }
            result[kind, default: []].append((record.id, payload.config, payload.secret))
        }
        return result
    }
}
