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

@MainActor
enum StorageDiagnose {

    static let environmentKey = "ORZMC_STORAGE_DIAGNOSE"

    /// 固定的探针 id（两端共用，读写同一个键）。
    static let probeID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C")!

    static var isRequested: Bool {
        let value = ProcessInfo.processInfo.environment[environmentKey]
        return ["write", "read", "delete"].contains(value ?? "")
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
