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
                    // **一行放完**：标题 + 值 + Stepper。
                    // 不用 `LabeledContent`：iPhone 宽度下它会自己折成上下两行
                    // （真机反馈"「分配内存」一行、数值+stepper 另一行"，看着很散）。
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        Text("Allocated memory")
                        Spacer(minLength: OrzMCTheme.Spacing.sm)
                        Text("\(Int(draft)) GB")
                            .font(OrzMCTheme.Typography.numeric)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if memory.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving memory")
                        }
                        Stepper("Allocated memory", value: Binding(get: { draft }, set: onEdit), in: 2...16, step: 1)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    .disabled(isBusy || serverStatus != .OFFLINE)

                    if memory.isDirty || memory.isSaving {
                        // ⚠️ 按钮必须各自加 `.borderless`：在 Form 行里，多个默认样式 Button 会被
                        // 合并成一个点击区域，点「还原」实际触发的还是第一个按钮（保存）——
                        // 真机反馈"还原和保存表现相同、点还原不复原"就是这个。
                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Button("Save", action: onSave)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!canSave)
                            Button("Revert", action: onRevert)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
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
