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

    /// 服务端回的是**命令错误**而不是名单。典型：
    ///
    /// ```
    /// Unknown or incomplete command, see below for error
    /// banlist list<--[HERE]
    /// ```
    ///
    /// 真机实测：Paper 的 `/banlist` 不接受 `list` 参数，`banlist list` 会返回这段，
    /// 旧解析把它当成了"一个叫 `banlist list<--[HERE]` 的玩家"。凡是这类回复一律当"拿不到"。
    public static func isCommandError(_ reply: String) -> Bool {
        let text = reply.lowercased()
        return text.contains("<--[here]")
            || text.contains("unknown or incomplete command")
            || text.contains("unknown command")
            || text.contains("incorrect argument")
            || text.contains("usage:")
    }

    /// `list`：`There are 2 of a max of 20 players online: alice, bob`
    public static func onlinePlayers(from reply: String) -> [String] {
        guard !isCommandError(reply), let tail = tailAfterColon(in: reply) else { return [] }
        return splitNames(tail)
    }

    /// `whitelist list`：`There are 2 whitelisted player(s): alice, bob`
    public static func whitelisted(from reply: String) -> [String] {
        guard !isCommandError(reply), let tail = tailAfterColon(in: reply) else { return [] }
        return splitNames(tail)
    }

    /// `banlist`：返回 `(名字, 原因?)`。
    ///
    /// 两种真实形态都要处理（实测同一台 Paper）：
    ///
    /// ```
    /// There are 2 ban(s):
    /// alice was banned by Console: griefing
    /// bob (cheating)
    /// ```
    ///
    /// 以及 **换行被吞掉**、整段连成一行的情况：
    ///
    /// ```
    /// There are 7 ban(s):176.65.148.132 was banned by Console: 你已被此服务器封禁！king was banned by ...
    /// ```
    ///
    /// 后者不能按逗号/换行切，否则整段会被当成"一个玩家名"（真机反馈"封禁列表像一段文本"）。
    /// 名字在 Minecraft 里不含空格，所以按 `名字 + was banned by 来源:` 这个结构切最稳。
    public static func banned(from reply: String) -> [(name: String, reason: String?)] {
        guard !isCommandError(reply) else { return [] }

        if let structured = bannedByBanListWording(reply), !structured.isEmpty {
            return structured
        }

        guard let tail = tailAfterColon(in: reply) else { return [] }
        return splitEntries(tail).compactMap { entry in
            let (head, reason) = splitReason(entry)
            let name = head.trimmingCharacters(in: .whitespacesAndNewlines)
            // `-` / `none` 都是"没有"，不是玩家名。
            guard !name.isEmpty, name != "-", name.lowercased() != "none" else { return nil }
            return (name, reason)
        }
    }

    /// 解析 `"<名字> was banned by <来源>: <原因>"` 这种结构（可连续出现、行内无分隔符）。
    static func bannedByBanListWording(_ reply: String) -> [(name: String, reason: String?)]? {
        // 名字：用户名（字母数字下划线）或 IP（数字点）。不含空格。
        let pattern = "([A-Za-z0-9_.\\-]{2,45})\\s+was\\s+banned\\s+by\\s+([^:]{1,40}):\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = reply as NSString
        let matches = regex.matches(in: reply, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var entries: [(String, String?)] = []
        for (index, match) in matches.enumerated() {
            let name = ns.substring(with: match.range(at: 1))
            let source = ns.substring(with: match.range(at: 2))
            let reasonStart = match.range.location + match.range.length
            let reasonEnd = index + 1 < matches.count
                ? matches[index + 1].range.location
                : ns.length
            guard reasonEnd > reasonStart else {
                entries.append((name, source))
                continue
            }
            let rawReason = ns.substring(with: NSRange(location: reasonStart, length: reasonEnd - reasonStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // "Server"/"Console" 这类来源没信息量；有自定义原因时优先展示原因。
            let reason = rawReason.isEmpty ? source : rawReason
            entries.append((name, reason))
        }
        return entries
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
