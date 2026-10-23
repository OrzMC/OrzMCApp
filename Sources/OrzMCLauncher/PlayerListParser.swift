//
//  PlayerListParser.swift
//  OrzMCLauncher
//

import Foundation

/// 把 RCON 的**人话回复**解析成玩家名单。
///
/// 服务端返回的是给控制台看的英文/本地化句子，例如：
///
/// ```
/// There are 2 of a max of 20 players online: alice, bob
/// There are 1 whitelisted player(s): alice
/// There are 1 ban(s):
/// alice (griefing)
/// ```
///
/// 不同版本 / 不同核心（Paper / Fabric / 原版）措辞会略有差异，所以解析**按结构**来：
/// 冒号后（或换行后）用逗号/换行切分，去掉 `(原因)` 这种尾巴。解析不出来就返回空数组，
/// 让界面显示"未获取"，而不是把整句当成人名。
public enum PlayerListParser {

    /// `list`：`There are 2 of a max of 20 players online: alice, bob`
    public static func onlinePlayers(from reply: String) -> [String] {
        guard let tail = tailAfterColon(in: reply) else { return [] }
        return splitNames(tail)
    }

    /// `whitelist list`：`There are 2 whitelisted player(s): alice, bob`
    public static func whitelisted(from reply: String) -> [String] {
        guard let tail = tailAfterColon(in: reply) else { return [] }
        return splitNames(tail)
    }

    /// `banlist list`：名字后面常跟 `(原因)`，甚至一行一个。返回 `(名字, 原因?)`。
    public static func banned(from reply: String) -> [(name: String, reason: String?)] {
        guard let tail = tailAfterColon(in: reply) else { return [] }
        return splitEntries(tail).compactMap { entry in
            let (head, reason) = splitReason(entry)
            let name = head.trimmingCharacters(in: .whitespacesAndNewlines)
            // `-` / `none` 都是"没有"，不是玩家名。
            guard !name.isEmpty, name != "-", name.lowercased() != "none" else { return nil }
            return (name, reason)
        }
    }

    // MARK: - 内部

    /// 取出冒号/换行之后的正文；没有正文（`... online:` 后面是空的）返回 `nil`。
    static func tailAfterColon(in reply: String) -> String? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let colon = text.firstIndex(of: ":") {
            let tail = String(text[text.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty ? nil : tail
        }
        // 有的核心直接换行然后一行一个名字
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return nil }
        return lines.dropFirst().joined(separator: "\n")
    }

    /// 逗号 / 换行 / 顿号切分，去掉空项与 `-`（表示"没有"）。
    static func splitNames(_ text: String) -> [String] {
        splitEntries(text)
            .map { splitReason($0).name }
            .filter { !$0.isEmpty && $0 != "-" }
    }

    static func splitEntries(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `alice (griefing)` → `("alice", "griefing")`；没有括号就只有名字。
    static func splitReason(_ entry: String) -> (name: String, reason: String?) {
        guard let open = entry.firstIndex(of: "("), entry.hasSuffix(")") else {
            return (entry, nil)
        }
        let name = String(entry[entry.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        let reason = String(entry[entry.index(after: open)..<entry.index(before: entry.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        return (name, reason.isEmpty ? nil : reason)
    }
}
