//
//  ExarotonAPI+.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import Foundation
import ExarotonHTTP
import ExarotonWebSocket
import OrzMCRemoteHosting

typealias ExarotonServer = ExarotonHTTP.Components.Schemas.Server
extension ExarotonServer: @retroactive Identifiable {}
extension ExarotonServer {

    var detail: String? {
        var ret = ""
        if let software {
            ret += "\(software.name ?? "-") \(software.version ?? "-")"
        }
        if let players {
            ret += " - (\(players.count ?? 0)/\(players.max ?? 0))"
        }
        return ret
    }

    var serverStatus: ServerStatus? {
        guard let status
        else {
            return nil
        }
        // HTTP 侧枚举来自 openapi 生成代码，取值范围可能比 WebSocket 侧更新；
        // 对不上时退化成 `.UNKNOWN`（界面显示"未知"，不再是"什么都不显示"）。
        return ServerStatus(rawValue: status.rawValue) ?? .UNKNOWN
    }

    var staticAddress: String? {
        guard let address, let port
        else {
            return nil
        }
        return "\(address):\(String(port))"
    }

    var dynamicAddress: String? {
        guard let host, let port
        else {
            return nil
        }
        return "\(host):\(String(port))"
    }

    var hasAddress: Bool {
        return staticAddress?.isEmpty == false || dynamicAddress?.isEmpty == false
    }
}

typealias ExarotonCreditPool = ExarotonHTTP.Components.Schemas.CreditPool
extension ExarotonCreditPool: @retroactive Identifiable {}
typealias ExarotonCreditMember = ExarotonHTTP.Components.Schemas.CreditPoolMember
extension ExarotonCreditMember: @retroactive Identifiable {
    public var id: String { account ?? name ?? "" }
}

// WebSocket
typealias ServerStatus = ExarotonWebSocket.ServerStatus
extension ServerStatus {
    var remoteHostingState: RemoteServerState {
        switch self {
        case .OFFLINE:
            return .offline
        case .ONLINE:
            return .online
        case .STARTING, .LOADING, .PENDING, .PREPARING, .TRANSFERRING:
            return .starting
        case .STOPPING, .SAVING:
            return .stopping
        case .RESTARTING:
            return .restarting
        // `.UNKNOWN`（SDK 没见过的状态码）和崩溃一样：状态不确定，按 unknown 处理。
        case .CRASHED, .UNKNOWN:
            return .unknown
        }
    }
}

extension ExarotonWebSocket.Server {
    var serverInfo: ExarotonServer {
        get throws {
            let data = try JSONEncoder().encode(self)
            let serverInfo = try JSONDecoder().decode(ExarotonServer.self, from: data)
            return serverInfo
        }
    }
}

typealias ServerStats = ExarotonWebSocket.Stats
extension ServerStats {

    var cpuUsageRange: ClosedRange<Double> { 0...Double(100 * cpu.limit) }
    var cpuUsage: Double { cpu.percent.validValudInRange(cpuUsageRange) }
    var cpuUsageLabel: String { String(localized: "CPU × \(cpu.limit)") }
    var cpuUsageDesc: String { "\(cpu.percent.displayString)%" }

    var memUsageRange: ClosedRange<Double> { 0...100 }
    var memUsage: Double { memory.percent.validValudInRange(memUsageRange) }
    var memUsageGB: Double { memory.usage * 100 / memory.percent / Double(1024 * 1024 * 1024)  }
    var memUsageLabel: String { String(localized: "Memory (\(memUsageGB.displayString) GB)") }
    var memUsageDesc: String { "\(memory.percent.displayString)%" }

}

typealias ServerTick = ExarotonWebSocket.Tick
extension ServerTick {
    var usageLabel: String { String(localized: "Tick: \(averageTickTime.displayString)") }
}

typealias ServerHeap = ExarotonWebSocket.Heap
extension ServerHeap {
    var usageLabel: String { String(localized: "Heap: \(usageGB.displayString) GB") }
    var usageGB: Double { Double(usage) / Double(1024 * 1024 * 1024) }
}
extension Double {
    var displayString: String { String(format: "%.2lf", self) }
    func validValudInRange(_ range: ClosedRange<Double>) -> Double {
        let ret = max(range.lowerBound, min(self, range.upperBound))
        return ret
    }
}

