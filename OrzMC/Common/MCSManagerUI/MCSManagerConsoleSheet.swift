//
//  MCSManagerConsoleSheet.swift
//  OrzMC
//
//  P2-7 第 5 步（界面）：MCSManager 实例的控制台。
//
//  与 exaroton/本地服务端**共用同一套渲染**：`ConsoleTextParser`（按 Unicode 标量解析，
//  `\r` 覆盖式进度条不会丢行）+ `ConsoleLineText`（ANSI / `§` 颜色）。这里只负责
//  "取日志尾部 + 发命令 + 自动刷新"。
//
//  MCSM 没有 WebSocket：控制台是**轮询**面板的 `outputlog`（纯文本尾部），
//  刷新间隔比状态轮询快一点（3 秒），因为用户正盯着它看。
//

import OrzMCDesignSystem
import OrzMCFoundation
import OrzMCRemoteHosting
import SwiftUI

struct MCSManagerConsoleSheet: View {

    let instance: MCSManagerInstance
    /// 面板模型（同一个 `MCSManagerModel`，动作/命令都走它，互斥与错误面一致）。
    let model: MCSManagerModel

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var command = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadedAt: Date?

    /// 控制台轮询间隔：比状态轮询（10 秒）快，用户正盯着看。
    private static let refreshInterval: Duration = .seconds(3)

    private var state: RemoteServerState { model.state(of: instance) }

    private var lines: [String] {
        ConsoleTextParser.lines(in: text)
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
        .task { await refreshLoop() }
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
            OrzMCStatusBadge(
                verbatim: state.localizedTitle,
                style: state.statusStyle
            )
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .accessibilityLabel(String(localized: "Refresh"))
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
            // 命令的回显在下一轮轮询里出现，不用额外等待。
        }
    }

    private func refreshLoop() async {
        await reload()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            text = try await model.outputLog(for: instance)
            errorMessage = nil
            lastLoadedAt = Date()
        } catch {
            errorMessage = MCSManagerErrorText.describe(error)
        }
    }
}
