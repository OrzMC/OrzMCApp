//
//  StorageDiagnose.swift
//  OrzMC
//
//  **仅 DEBUG** 的存储验收：不点界面也能验证「保存方式」三档到底落在哪、能不能跨设备看到。
//
//  用法（两端各跑一次）：
//    ORZMC_STORAGE_DIAGNOSE=write   # 往 iCloud 档位写一条探针（含时间戳）
//    ORZMC_STORAGE_DIAGNOSE=read    # 读回探针，打印它是不是另一台设备写的
//
//  为什么需要它：iCloud 同步只能在"真机 + 同一 Apple 账号"上验，而 agent 点不动手机屏幕；
//  这个钩子把结论打到 stderr，`devicectl --console` 直接就能读。
//

#if DEBUG
import Foundation
import OrzMCFoundation
import OrzMCLauncher

@MainActor
enum StorageDiagnose {

    static let environmentKey = "ORZMC_STORAGE_DIAGNOSE"

    /// 固定的探针 id（两端共用，读写同一个键）。
    static let probeID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C")!

    static var isRequested: Bool {
        let value = ProcessInfo.processInfo.environment[environmentKey]
        return [
            "write", "read", "delete", "report", "moveprobe",
            "cloudprobe", "cloudread", "cloudclean", "cloudpushall", "keychainscan",
        ].contains(value ?? "")
    }

    static func runIfRequested() async {
        guard let action = ProcessInfo.processInfo.environment[environmentKey] else { return }
        var report: [String: String] = [
            "action": action,
            "device": ProcessInfo.processInfo.hostName,
            "sharedAccessGroup": ServerSecretsStore.sharedAccessGroup() ?? "nil",
            "iCloudAvailable": String(ServerSecretsStore.isAvailable(.iCloud)),
            "at": ISO8601DateFormatter().string(from: Date()),
        ]

        switch action {
        case "cloudpushall":
            // **恢复用**：把本机现存的自建/Exaroton/MCSM 记录整条推到云端（会覆盖同 id 的云端副本）。
            var pushed: [String] = []
            let selfHosted = SelfHostedServersModel()
            for profile in selfHosted.profiles.servers {
                guard let config = try? JSONEncoder().encode(profile) else { continue }
                let secret = ServerSecretsStore.secret(
                    id: profile.id, provider: .selfHostedRCON, mode: profile.storageMode
                ) ?? ""
                if CloudRecords.push(id: profile.id, kind: .selfHosted, config: config, secret: secret) {
                    pushed.append("selfHosted:\(profile.displayName)")
                }
            }
            let accounts = ExarotonAccountsModel()
            for account in accounts.accounts {
                guard let config = try? JSONEncoder().encode(account) else { continue }
                let token = ServerSecretsStore.secret(
                    id: account.id, provider: .exarotonToken, mode: account.storageMode
                ) ?? ""
                if CloudRecords.push(id: account.id, kind: .exaroton, config: config, secret: token) {
                    pushed.append("exaroton:\(account.displayName)")
                }
            }
            let mcsm = MCSManagerPanelsModel()
            for panel in mcsm.panels {
                guard let config = try? JSONEncoder().encode(panel) else { continue }
                let key = ServerSecretsStore.secret(
                    id: panel.id, provider: .mcsmAPIKey, mode: panel.storageMode
                ) ?? ""
                if CloudRecords.push(id: panel.id, kind: .mcsm, config: config, secret: key) {
                    pushed.append("mcsm:\(panel.label)")
                }
            }
            report["pushed"] = pushed.joined(separator: " ; ")
            report["cloudRecords"] = String(ServerSecretsStore.cloudRecords().count)
        case "keychainscan":
            // 恢复用：列出本机 Keychain 里**还有哪些业务键**（只列账户名，不读内容）。
            report["accounts"] = ServerSecretsStore.debugKeychainAccounts().joined(separator: " ; ")
        case "cloudprobe", "cloudread", "cloudclean":
            // 整条记录（配置 + 凭据）的云端同步自检：**合成**一台服务器，走与界面相同的 `save` 路径。
            let syntheticID = UUID(uuidString: "00000000-0000-0000-0000-00000000B22D")!
            let model = SelfHostedServersModel()
            switch action {
            case "cloudprobe":
                var profile = SelfHostedServerProfile(
                    id: syntheticID,
                    name: "云同步测试",
                    host: "cloud-sync.invalid",
                    port: 25565,
                    rconPort: 25575,
                    rconEnabled: true
                )
                profile.storageMode = .iCloud
                model.save(profile, rconPassword: "probe-password")
            case "cloudread":
                model.syncWithCloud()
            default:
                model.remove(syntheticID)
                CloudRecords.remove(id: syntheticID, kind: .selfHosted)
            }
            let local = model.profiles.servers.first { $0.id == syntheticID }
            report["localFound"] = local == nil ? "no" : "yes"
            report["localMode"] = local?.storageMode.rawValue ?? "-"
            report["localName"] = local?.name ?? "-"
            report["localSecret"] = (ServerSecretsStore.secret(
                id: syntheticID, provider: .selfHostedRCON, mode: .iCloud
            )?.isEmpty == false) ? "yes" : "no"
            let cloud = ServerSecretsStore.cloudRecords()
            report["cloudRecords"] = String(cloud.count)
            report["cloudDetail"] = cloud
                .map { "\($0.provider):\($0.id.uuidString.prefix(8))" }
                .sorted()
                .joined(separator: " ")
        case "report":
            // **只读自检**：把两端现存的记录逐条过一遍，看凭据还能不能读到（不打印任何凭据内容）。
            var entries: [[String: String]] = []
            let profiles = SelfHostedProfilesStore.load()
            for profile in profiles.servers {
                let secret = ServerSecretsStore.secret(
                    id: profile.id, provider: .selfHostedRCON, mode: profile.storageMode
                )
                entries.append([
                    "kind": "selfHosted",
                    "name": profile.name.isEmpty ? profile.host : profile.name,
                    "mode": profile.storageMode.rawValue,
                    "hasSecret": (secret?.isEmpty == false) ? "yes" : "no",
                    "length": String(secret?.count ?? 0),
                ])
            }
            if let data = UserDefaults.standard.data(forKey: ExarotonAccountsModel.accountsKey),
               let accounts = try? JSONDecoder().decode([ExarotonAccount].self, from: data) {
                for account in accounts {
                    let token = ServerSecretsStore.secret(
                        id: account.id, provider: .exarotonToken, mode: account.storageMode
                    )
                    entries.append([
                        "kind": "exaroton",
                        "name": account.displayName,
                        "mode": account.storageMode.rawValue,
                        "hasSecret": (token?.isEmpty == false) ? "yes" : "no",
                        "length": String(token?.count ?? 0),
                    ])
                }
            }
            for panel in MCSManagerCredentials.panels() {
                let key = ServerSecretsStore.secret(
                    id: panel.id, provider: .mcsmAPIKey, mode: panel.storageMode
                )
                entries.append([
                    "kind": "mcsm",
                    "name": panel.label,
                    "mode": panel.storageMode.rawValue,
                    "hasSecret": (key?.isEmpty == false) ? "yes" : "no",
                    "length": String(key?.count ?? 0),
                ])
            }
            report["records"] = String(entries.count)
            report["okCount"] = String(entries.filter { $0["hasSecret"] == "yes" }.count)
            report["missingCount"] = String(entries.filter { $0["hasSecret"] != "yes" }.count)
            let detail = entries.map { e in
                "\(e["kind"] ?? "?") | \(e["name"] ?? "?") | mode=\(e["mode"] ?? "?") | secret=\(e["hasSecret"] ?? "?") | len=\(e["length"] ?? "0")"
            }
            report["detail"] = detail.joined(separator: " ;; ")
        case "moveprobe":
            // 迁移自检（合成记录，不碰真实数据）：device → iCloud → installation → device，每步读回比对。
            let payload = "move-probe-\(report["at"] ?? "")"
            var steps: [String] = []
            func record(_ ok: Bool, _ step: String) { steps.append("\(step)=\(ok ? "ok" : "FAIL")") }

            _ = ServerSecretsStore.save(payload, id: probeID, provider: .selfHostedRCON, mode: .device)
            record(ServerSecretsStore.secret(id: probeID, provider: .selfHostedRCON, mode: .device) == payload,
                   "device(write)")

            func move(_ from: ServerRecordStorageMode, _ to: ServerRecordStorageMode) {
                do {
                    try ServerSecretsStore.move(id: probeID, provider: .selfHostedRCON, from: from, to: to)
                    // 只校验目标端读得到；**来源是否清空在公共 API 上观察不到** ——
                    // `.device` 有回退读（切档位时"看不见密码"更糟），所以读 source 会拿到目标那份。
                    record(ServerSecretsStore.secret(id: probeID, provider: .selfHostedRCON, mode: to) == payload,
                           "\(from.rawValue)->\(to.rawValue)")
                } catch {
                    steps.append("\(from.rawValue)->\(to.rawValue)=FAIL(\(error))")
                }
            }
            move(.device, .iCloud)
            move(.iCloud, .installation)
            move(.installation, .device)

            ServerSecretsStore.remove(id: probeID, provider: .selfHostedRCON)
            record(ServerSecretsStore.secret(id: probeID, provider: .selfHostedRCON, mode: .device) == nil, "cleanup")
            report["steps"] = steps.joined(separator: " ")
            report["allOK"] = String(!steps.contains { $0.contains("FAIL") })
        case "write":
            let payload = "probe:\(report["at"] ?? ""):\(report["device"] ?? "")"
            let ok = ServerSecretsStore.save(
                payload, id: probeID, provider: .selfHostedRCON, mode: .iCloud
            )
            report["writeOK"] = String(ok)
            report["written"] = ok ? payload : "-"
            // 立刻回读，确认写入确实落在这个后端里。
            report["readBack"] = ServerSecretsStore.secret(
                id: probeID, provider: .selfHostedRCON, mode: .iCloud
            ) ?? "nil"
        case "delete":
            ServerSecretsStore.remove(id: probeID, provider: .selfHostedRCON)
            report["afterDelete"] = ServerSecretsStore.secret(
                id: probeID, provider: .selfHostedRCON, mode: .iCloud
            ) ?? "nil"
        case "read":
            let value = ServerSecretsStore.secret(id: probeID, provider: .selfHostedRCON, mode: .iCloud)
            report["found"] = value == nil ? "no" : "yes"
            report["value"] = value ?? "-"
        default:
            return
        }

        // 同时写进 Caches（真机可用 `devicectl device copy` 取回）与 stderr（`--console` 直接看）。
        let json = (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        FileHandle.standardError.write(Data(("storage-diagnose: \(json)\n").utf8))
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("orzmc-storage-diagnose.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)

        // 无界面验收：报告写完就退出（两端都不留一个空跑的进程）。
        try? await Task.sleep(for: .seconds(1))
        #if os(macOS)
        // macOS 上退出要过 AppKit（这个文件不能用 `import AppKit`，否则 iOS 编译失败）：
        // 用 `exit(0)` 在无界面诊断里是安全的——不写任何需要落盘的运行状态。
        exit(0)
        #else
        exit(0)
        #endif
    }
}
#endif
