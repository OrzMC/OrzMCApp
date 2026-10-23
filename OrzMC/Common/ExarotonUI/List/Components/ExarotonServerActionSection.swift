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

    @State private var confirmStop = false
    @State private var confirmRestart = false
    /// 最近一次动作，失败后就地给「重试」用，不必让用户回列表再进详情。
    @State private var lastAction: RemoteServerAction?

    private var serverID: String { server.id ?? "" }

    @ViewBuilder
    private func actionButtons(axis: Axis) -> some View {
        let stack = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: OrzMCTheme.Spacing.sm))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: OrzMCTheme.Spacing.sm))

        stack {
            Button {
                perform(.start)
            } label: {
                Label("Start Server", systemImage: "play.fill")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPerform(.start))

            Button {
                confirmStop = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .disabled(!canPerform(.stop))

            Button {
                confirmRestart = true
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .disabled(!canPerform(.restart))

            if axis == .horizontal { Spacer(minLength: 0) }
        }
    }

    var body: some View {
        Section("Actions") {
            // 小屏（iPhone SE）上"启动服务器 + 停止 + 重启"以前会挤成两行、ControlGroup 还会渲染成
            // 一个没有文字的方块。改成三个普通按钮，各自单行；放不下就整组换行（`ViewThatFits`）。
            ViewThatFits(in: .horizontal) {
                actionButtons(axis: .horizontal)
                actionButtons(axis: .vertical)
            }
            .disabled(model.gate.pendingActions.contains(serverID))

            feedback

            OrzMCBanner(
                "Actions run on exaroton's side. Players connected to the server are disconnected by Stop/Restart.",
                role: .info
            )
        }
        // 破坏性/会断线的远程操作先确认：与本地服务端的 Stop/Restart 保持同一套交互。
        .confirmationDialog("Stop Server?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { perform(.stop) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server saves and shuts down; connected players are disconnected.")
        }
        .confirmationDialog("Restart Server?", isPresented: $confirmRestart) {
            Button("Restart") { perform(.restart) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server restarts; players are disconnected during the restart.")
        }
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
