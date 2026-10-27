//
//  MCSManagerConsoleSheet.swift
//  OrzMC
//
//  P2-7 第 5 步（界面）+ B1（实时流）：MCSManager 实例的控制台。
//
//  与 exaroton/本地服务端**共用同一套渲染**：`ConsoleTextParser`（按 Unicode 标量解析，
//  `\r` 覆盖式进度条不会丢行）+ `ConsoleLineText`（ANSI / `§` 颜色）。这里只负责
//  "拿到输出 + 发命令"。
//
//  输出有两条路（B1 起）：
//   1. **实时流**（优先）：`stream_channel` 换一次性口令 → 连面板 socket.io → 节点 stdout 一条条推来；
//   2. **轮询**（回退）：面板给不出通道 / 节点在 NAT 后面连不上时，3 秒一次取 `outputlog` 尾部。
//  两者共用 `ConsoleTextBuffer`（超长按行裁剪），渲染路径完全一样 —— 用户看到的都是同一份文本。
//

import MCSMAPI
import MCSMStream
import OrzMCDesignSystem
import OrzMCFoundation
import OrzMCRemoteHosting
import SwiftUI

struct MCSManagerConsoleSheet: View {

    let instance: MCSManagerInstance
    /// 面板模型（同一个 `MCSManagerModel`，动作/命令都走它，互斥与错误面一致）。
    let model: MCSManagerModel

    @Environment(\.dismiss) private var dismiss

    /// 控制台文本的累积器（实时流追加 / 轮询整段替换）。
    @State private var buffer = ConsoleTextBuffer()
    @State private var command = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadedAt: Date?
    /// 实时流状态（顶部那个小徽标用）。
    @State private var streamState = StreamState.connecting

    /// 控制台轮询间隔（**仅回退路径**用）：比状态轮询（10 秒）快，用户正盯着看。
    private static let refreshInterval: Duration = .seconds(3)

    private var state: RemoteServerState { model.state(of: instance) }

    private var lines: [String] {
        ConsoleTextParser.lines(in: buffer.text)
    }

    /// 输出是从哪来的。
    private enum StreamState: Equatable {
        /// 正在申请通道 / 连 socket.io。
        case connecting
        /// 实时流已就绪。
        case live
        /// 回退轮询（附原因，界面上说明一句）。
        case polling(reason: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            header
            console
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            commandBar
        }
        .padding(OrzMCTheme.Spacing.md)
        // ⚠️ 最小尺寸只给 **macOS**（桌面上 sheet 太窄看不出日志）；
        // iPhone SE 只有 375pt 宽，硬写 `minWidth: 420` 会把标题、日志、发送按钮都挤出屏幕
        // （真机/模拟器实测：内容被裁掉左右两边，UI 用例也因此查不到控制台容器）。
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .task { await runConsole() }
    }

    // MARK: - 组件

    private var header: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.nickname)
                    .font(.headline)
                if let lastLoadedAt {
                    Text(
                        String(
                            localized: "Updated \(lastLoadedAt.formatted(date: .omitted, time: .standard))"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(streamBadgeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mcsm.consoleStreamState")
            OrzMCStatusBadge(
                verbatim: state.localizedTitle,
                style: state.statusStyle
            )
            Button {
                Task { await reloadHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .accessibilityLabel(String(localized: "Refresh"))
        }
    }

    private var streamBadgeText: String {
        switch streamState {
        case .connecting: return String(localized: "Connecting…")
        case .live: return String(localized: "Live")
        case .polling: return String(localized: "Polling")
        }
    }

    private var console: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    Text(isLoading ? String(localized: "Loading…") : String(localized: "No output yet"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        ConsoleLineText(segments: ConsoleTextParser.parse(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(OrzMCTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .consoleSurface()
        .defaultScrollAnchor(.bottom)
        .textSelection(.enabled)
        // `children: .contain`：容器上的 identifier 会**下发给子元素**并覆盖子元素自己的 id，
        // 不加这个，UI 用例就查不到 `mcsm.console` 本身（踩过：MCSManager 分组同理）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcsm.console")
    }

    private var commandBar: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            TextField(String(localized: "Console command…"), text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit { send() }
                .disabled(state != .online || model.isBusy(instance))
                .accessibilityIdentifier("mcsm.commandField")

            Button {
                send()
            } label: {
                Label(String(localized: "Send"), systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || state != .online
                    || model.isBusy(instance)
            )
            .accessibilityIdentifier("mcsm.sendCommand")
        }
    }

    // MARK: - 行为

    private func send() {
        let pending = command
        command = ""
        Task {
            // 发不出去就把内容还给用户，别默默丢掉。
            if await !model.sendCommand(pending, to: instance) {
                command = pending
            }
            // 命令的回显在下一段输出里出现（实时流几乎是立刻，轮询要等下一轮）。
        }
    }

    /// 先给一屏历史（避免"连上之前界面空的"），再尝试实时流；不行就轮询。
    private func runConsole() async {
        await reloadHistory()
        await streamOutput()
    }

    /// 实时流：成功就一直收；任何失败都退回轮询（不打扰用户，只在顶部标一格）。
    private func streamOutput() async {
        guard let panelURL = model.panelURL else {
            await pollLoop(reason: String(localized: "Panel not configured"))
            return
        }

        let client = MCSMStreamClient { [model, instance, panelURL] in
            guard let channel = try await model.streamChannel(for: instance) else {
                throw MCSMStreamEndpoint.Error.invalidAddress("panel has no stream channel")
            }
            return try MCSMStreamEndpoint(channel: channel, panelURL: panelURL)
        }

        for await event in await client.events() {
            switch event {
            case .connecting:
                streamState = .connecting
            case .ready:
                streamState = .live
                errorMessage = nil
                lastLoadedAt = Date()
            case let .output(text):
                buffer.append(text)
                lastLoadedAt = Date()
            case .lifecycle:
                // 实例停了/开了：状态由 `RemoteStatusCenter` 统一管，这里只把时间戳动一下，
                // 让用户知道流还在。
                lastLoadedAt = Date()
            case let .fallback(reason):
                // 实时流不可用（面板老版本 / 节点在 NAT 后面）：退回轮询，功能不降级。
                await client.close()
                await pollLoop(reason: reason)
                return
            }
        }
        // 流正常结束（实例停了 / 面板重启）：交给状态刷新去反映，别一直转圈。
        await client.close()
    }

    /// 回退路径：定时取日志尾部（B1 之前的老行为）。
    private func pollLoop(reason: String) async {
        streamState = .polling(reason: reason)
        while !Task.isCancelled {
            await reloadHistory()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// 取一次日志尾部（首次加载 / 用户点刷新 / 轮询路径）。
    private func reloadHistory() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await model.outputLog(for: instance)
            // 轮询拿到的是**整段尾部**，直接替换；实时流是增量，走 `append`。
            buffer.reset(to: text)
            errorMessage = nil
            lastLoadedAt = Date()
        } catch {
            errorMessage = MCSManagerErrorText.describe(error)
        }
    }
}
