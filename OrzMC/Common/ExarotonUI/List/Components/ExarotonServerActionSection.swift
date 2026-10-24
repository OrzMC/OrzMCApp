//
//  ExarotonServerActionSection.swift
//  OrzMC
//
//  Created by Codex on 2026/5/22.
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

/// 远程生命周期动作：开始 / 停止 / 重启。
///
/// - 互斥由模型负责（`RemoteActionGate`：首次 `await` 前占用实例），按钮 disabled 只是提示；
/// - 成功只承诺「已提交请求」，真实运行状态等服务端状态推送；
/// - 失败就地展示错误并可重试，不再弹必须确认的全局框。
struct ExarotonServerActionSection: View {
    @Environment(ExarotonServerModel.self) private var model

    let server: ExarotonServer
    let status: ServerStatus

    private let actionPolicy = RemoteServerListPolicy()

    /// 确认弹窗的开关由**详情页根部**持有：`confirmationDialog` 挂在 Section 上时锚点会跑到行上。
    @Binding var confirmStop: Bool
    @Binding var confirmRestart: Bool
    /// 最近一次动作，失败后就地给「重试」用，不必让用户回列表再进详情。
    @State private var lastAction: RemoteServerAction?

    private var serverID: String { server.id ?? "" }

    /// 三个动作按钮。
    ///
    /// 用 `Button(_:systemImage:)`（**不要**自己塞 `Label`：在 Form 行里会被渲染成图标-only，
    /// 主按钮还会变成"蓝底蓝字"的空白色块——真机截图复现过）。`fixedSize()` 保证不换行，
    /// 放不下时由外层 `ViewThatFits` 换成竖排。
    private var startButton: some View {
        Button {
            perform(.start)
        } label: {
            // 用 System 图片 + Text 自己排（不要 `Label`：Form 行里会被渲染成图标-only/he 文字-only）。
            HStack(spacing: OrzMCTheme.Spacing.xs) {
                Image(systemName: "play.fill")
                Text("Start Server")
            }
            .frame(maxWidth: .infinity)      // 撑满整行，胶囊等宽
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canPerform(.start))
    }

    private var stopButton: some View {
        Button {
            confirmStop = true
        } label: {
            HStack(spacing: OrzMCTheme.Spacing.xs) {
                Image(systemName: "stop.fill")
                Text("Stop")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canPerform(.stop))
    }

    private var restartButton: some View {
        Button {
            confirmRestart = true
        } label: {
            HStack(spacing: OrzMCTheme.Spacing.xs) {
                Image(systemName: "arrow.clockwise")
                Text("Restart")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canPerform(.restart))
    }

    var body: some View {
        Section("Actions") {
            // iPhone 上横排三个带文字的按钮必然挤（iOS 26 会把标题压没、只剩图标）：
            // 直接竖排，每个按钮独占一行；macOS 窗口够宽，保持横排。
            #if os(iOS)
            VStack(spacing: OrzMCTheme.Spacing.sm) {
                startButton
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    stopButton
                    restartButton
                }
            }
            .disabled(model.gate.pendingActions.contains(serverID))
            #else
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                startButton
                stopButton
                restartButton
                Spacer(minLength: 0)
            }
            .disabled(model.gate.pendingActions.contains(serverID))
            #endif

            feedback

            OrzMCBanner(
                "Actions run on exaroton's side. Players connected to the server are disconnected by Stop/Restart.",
                role: .info
            )
        }
        // 确认弹窗**不挂在这里**：`confirmationDialog` 依附在 Section 上时，iPad/iPhone 会以
        // 该行作为 popover 锚点，弹到屏幕中间偏上、指哪儿打哪儿（真机反馈"锚点不正确"）。
        // 统一挂到详情页根部（见 `ExarotonServerDetail`），由页面用 `actionConfirmation` 承接。
    }


    // MARK: - 请求反馈（非模态，错误就地可重试）

    @ViewBuilder
    private var feedback: some View {
        if let message = model.actionMessages[serverID] {
            HStack {
                if model.gate.pendingActions.contains(serverID) {
                    ProgressView().controlSize(.small)
                }
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let failure = model.actionErrors[serverID] {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                OrzMCBanner(verbatim: failure, role: .error)
                if let lastAction {
                    Button("Retry", systemImage: "arrow.clockwise") {
                        perform(lastAction)
                    }
                    .disabled(!canPerform(lastAction))
                }
            }
        }
    }

    // MARK: - 动作

    private func canPerform(_ action: RemoteServerAction) -> Bool {
        !model.gate.isBusy(serverID: serverID) && actionPolicy.canPerform(action, on: status.remoteHostingState)
    }

    private func perform(_ action: RemoteServerAction) {
        guard let serverID = server.id else {
            model.errorMessage = String(localized: "Server ID is missing.")
            return
        }
        lastAction = action
        Task {
            switch action {
            case .start:
                _ = await model.startServer(serverId: serverID)
            case .stop:
                _ = await model.stopServer(serverId: serverID)
            case .restart:
                _ = await model.restartServer(serverId: serverID)
            }
        }
    }
}
