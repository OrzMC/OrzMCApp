//
//  ExarotonMemorySection.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

/// 远程服务器的内存：**草稿 → 明确保存 → 失败可回退**，全部收在一个 Section 里。
///
/// 以前 Stepper 在 `Actions` 里、Save/Revert 在另一个 Section、失败 banner 又漂在下面，
/// 一个概念散在三处。判定逻辑仍是纯值类型 `ServerMemoryState`（有单测）：
/// - 改 Stepper 只动草稿，不发请求；
/// - 保存失败时确认值不变、草稿保留 → 这里继续显示「Unsaved changes」并给出重试；
/// - 读取失败不隐藏整行，而是「Unavailable + Retry」+ 原因。
struct ExarotonMemorySection: View {
    @Environment(ExarotonServerModel.self) private var model

    let serverID: String
    let serverStatus: ServerStatus?
    let memory: ServerMemoryState
    let onEdit: (Int32) -> Void
    let onSave: () -> Void
    let onRevert: () -> Void
    let onReload: () async -> Void

    private var loadFailure: String? { memory.isLoaded ? nil : model.memoryLoadErrors[serverID] }
    private var saveFailure: String? { memory.isDirty ? model.memoryErrors[serverID] : nil }
    private var isBusy: Bool { memory.isSaving || model.gate.isBusy(serverID: serverID) }
    private var canSave: Bool {
        memory.canSave && serverStatus == .OFFLINE && !model.gate.isBusy(serverID: serverID)
    }

    var body: some View {
        if memory.draft != nil || loadFailure != nil {
            Section("Memory") {
                if let draft = memory.draft {
                    LabeledContent("Allocated memory") {
                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Text("\(Int(draft)) GB")
                                .font(OrzMCTheme.Typography.numeric)
                                .foregroundStyle(.secondary)
                            Stepper("Allocated memory", value: Binding(get: { draft }, set: onEdit), in: 2...16, step: 1)
                                .labelsHidden()
                            if memory.isSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Saving memory")
                            }
                        }
                    }
                    .disabled(isBusy || serverStatus != .OFFLINE)

                    if memory.isDirty || memory.isSaving {
                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Button("Save Memory", action: onSave)
                                .disabled(!canSave)
                            Button("Revert", action: onRevert)
                                .disabled(memory.isSaving)
                            if !memory.isSaving {
                                Text("Unsaved changes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if let saveFailure {
                        OrzMCBanner(verbatim: saveFailure, role: .error)
                    }
                } else if let loadFailure {
                    LabeledContent("Allocated memory") {
                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await onReload() }
                            }
                            .disabled(isBusy)
                        }
                    }
                    OrzMCBanner(verbatim: loadFailure, role: .error)
                }
            }
        }
    }
}
