//
//  MCStatusSummary.swift
//  OrzMCProtocol
//

import Foundation

/// 一次 SLP 查询的结果，**只保留界面要显示的东西**。
///
/// SLP 的 JSON 在不同版本/服务端上都长得不太一样（`description` 可能是纯字符串，
/// 也可能是 `{"text": ...}` 带 `extra`；`sample` 可能没有），所以这里用容错解析：
/// 解析失败不抛错，退化成"在线但没有细节"，免得一个字段缺失就让整张卡变红。
public struct MCStatusSummary: Equatable, Sendable {
    public var versionName: String?
    public var protocolVersion: Int?
    public var playersOnline: Int?
    public var playersMax: Int?
    /// 在线玩家列表（服务端可能隐藏；最多几十个名字）。
    public var sampleNames: [String]
    /// MOTD（已去掉 § 颜色码）。
    public var motd: String?
    /// TCP 往返时延（毫秒）。
    public var latencyMilliseconds: Int
    /// `data:image/png;base64,...`；界面按需解码。
    public var favicon: String?

    public init(
        versionName: String? = nil,
        protocolVersion: Int? = nil,
        playersOnline: Int? = nil,
        playersMax: Int? = nil,
        sampleNames: [String] = [],
        motd: String? = nil,
        latencyMilliseconds: Int = 0,
        favicon: String? = nil
    ) {
        self.versionName = versionName
        self.protocolVersion = protocolVersion
        self.playersOnline = playersOnline
        self.playersMax = playersMax
        self.sampleNames = sampleNames
        self.motd = motd
        self.latencyMilliseconds = latencyMilliseconds
        self.favicon = favicon
    }

    /// 解析 SLP 的 JSON 字符串（`status` 响应里的那一坨）。
    public static func parse(statusJSON: String, latencyMilliseconds: Int = 0) throws -> MCStatusSummary {
        guard let data = statusJSON.data(using: .utf8) else {
            throw MCStatusError.malformedStatus
        }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any] else {
            throw MCStatusError.malformedStatus
        }

        var summary = MCStatusSummary(latencyMilliseconds: latencyMilliseconds)

        if let version = object["version"] as? [String: Any] {
            summary.versionName = version["name"] as? String
            summary.protocolVersion = version["protocol"] as? Int
        }
        if let players = object["players"] as? [String: Any] {
            summary.playersOnline = players["online"] as? Int
            summary.playersMax = players["max"] as? Int
            if let sample = players["sample"] as? [[String: Any]] {
                summary.sampleNames = sample.compactMap { $0["name"] as? String }
            }
        }
        summary.motd = Self.plainText(fromDescription: object["description"])
        summary.favicon = object["favicon"] as? String
        return summary
    }

    /// `description` 可以是字符串，也可以是 `{"text":…, "extra":[…]}`（可嵌套）。
    static func plainText(fromDescription value: Any?) -> String? {
        switch value {
        case let text as String:
            return clean(text)
        case let object as [String: Any]:
            var parts: [String] = []
            if let text = object["text"] as? String { parts.append(text) }
            if let extra = object["extra"] as? [Any] {
                parts.append(contentsOf: extra.compactMap { plainText(fromDescription: $0) })
            }
            let joined = parts.joined()
            return joined.isEmpty ? nil : clean(joined)
        case let array as [Any]:
            let joined = array.compactMap { plainText(fromDescription: $0) }.joined()
            return joined.isEmpty ? nil : clean(joined)
        default:
            return nil
        }
    }

    /// 去掉 `§a` 这类颜色/格式码，并把换行保留（MOTD 常见两行）。
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?i)§[0-9a-fk-orx]",
            with: "",
            options: .regularExpression
        )
    }
}

public enum MCStatusError: Error, Equatable {
    /// 服务端返回的 JSON 结构不认识。
    case malformedStatus
    /// 端口没开 / 不是 Minecraft 服务端（握手被断开）。
    case notMinecraftServer
}
