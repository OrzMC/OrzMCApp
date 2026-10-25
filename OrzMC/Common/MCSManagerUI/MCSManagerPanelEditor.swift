//
//  MCSManagerPanelEditor.swift
//  OrzMC
//
//  添加 / 编辑 MCSManager 面板的表单（macOS + iOS 共用一套字段与校验）。
//
//  设计口径（2026-10-26，macOS 上手验收的反馈）：
//  - 表单在 macOS 上要给足宽度、不要用 iOS 的 `presentationDetents`（那是"半屏抽屉"语义）；
//  - 地址边输入边校验，错误就地提示，不要等点了保存才报；
//  - 提供「测试连接」：用还没保存的地址 + key 走一次 `GET /api/auth`，直接告诉用户
//    "连上了、是什么角色、名下几台实例" —— 比保存后盯着「加载中…」等 20 秒直观；
//  - 编辑时 Key 留空 = 不修改（只改地址/名称时不用重新粘一次 key）。
//

import OrzMCDesignSystem
import SwiftUI

struct MCSManagerPanelEditor: View {

    enum Mode: Equatable, Identifiable {
        case add
        case edit(MCSManagerPanel)

        /// `sheet(item:)` 的稳定 id：添加固定，编辑用面板 id（同一面板再次打开不会复用旧状态）。
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let panel): return panel.id.uuidString
            }
        }
    }

    let mode: Mode
    /// 返回 true = 保存成功（调用方据此关闭表单）。
    let onSave: (_ label: String, _ url: String, _ apiKey: String) -> Bool
    let onCancel: () -> Void

    @Environment(MCSManagerPanelsModel.self) private var mcsm

    @State private var label: String
    @State private var url: String
    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult: Equatable {
        /// 成功：给用户看的一句话（角色 + 实例数）。
        case success(String)
        /// 失败：面板自己的话或兜底文案。
        case failure(String)
    }

    init(
        mode: Mode,
        onSave: @escaping (String, String, String) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .add:
            _label = State(initialValue: "")
            _url = State(initialValue: "")
        case .edit(let panel):
            _label = State(initialValue: panel.label)
            _url = State(initialValue: panel.url.absoluteString)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// 输入地址能不能解析（空串不算"非法"，只是还不能保存）。
    private var urlIsValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || MCSManagerPanel.normalizedURL(from: trimmed) != nil
    }

    /// 编辑时 Key 可以留空（= 不改）；添加时必须填。
    private var canSave: Bool {
        let hasURl = !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && urlIsValid
        let hasKey = isEditing || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasURl && hasKey
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Panel name (optional)"), text: $label)
                        .accessibilityIdentifier("mcsm.labelField")
                    TextField(String(localized: "Panel address, e.g. panel.example.com"), text: $url)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mcsm.urlField")
                    if !urlIsValid {
                        Label(
                            String(localized: "The panel address is not valid."),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(OrzMCTheme.Palette.danger)
                    }
                } header: {
                    Text(String(localized: "Panel"))
                } footer: {
                    Text(
                        String(
                            localized: "Only the http(s) address of the panel is needed. A missing scheme defaults to https://."
                        )
                    )
                    .font(.caption)
                }

                Section {
                    SecureField(
                        isEditing
                            ? String(localized: "Leave empty to keep the current key")
                            : String(localized: "API Key"),
                        text: $apiKey
                    )
                    .accessibilityIdentifier("mcsm.apiKeyField")
                } header: {
                    Text(String(localized: "API Key"))
                } footer: {
                    Text(
                        String(
                            localized: "Create the key in the panel under your user profile. API Key access must be enabled in the panel settings."
                        )
                    )
                    .font(.caption)
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal.circle")
                            }
                            Text(String(localized: "Test Connection"))
                        }
                    }
                    .disabled(isTesting || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mcsm.testConnection")

                    if let testResult {
                        switch testResult {
                        case .success(let message):
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(OrzMCTheme.Palette.success)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(OrzMCTheme.Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } footer: {
                    Text(String(localized: "Uses the address and key above; nothing is saved until you press Save."))
                        .font(.caption)
                }

                if let error = mcsm.lastValidationError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(OrzMCTheme.Palette.danger)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                isEditing ? String(localized: "Edit Panel") : String(localized: "Add Panel")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if onSave(label, url, apiKey) {
                            testResult = nil
                        }
                    }
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mcsm.savePanel")
                }
            }
        }
        .frame(
            minWidth: Self.minWidth,
            idealWidth: Self.minWidth,
            minHeight: Self.minHeight,
            idealHeight: Self.minHeight
        )
    }

    // MARK: - 尺寸（macOS 上表单要有呼吸空间；iOS 用 detents 控制高度，这里不起作用）

    private static var minWidth: CGFloat {
        #if os(macOS)
        520
        #else
        0
        #endif
    }

    private static var minHeight: CGFloat {
        #if os(macOS)
        520
        #else
        0
        #endif
    }

    private func test() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        switch await mcsm.verifyConnection(rawURL: url, apiKey: apiKey, panelID: panelID) {
        case .connected(let message):
            testResult = .success(message)
        case .failed(let message):
            testResult = .failure(message)
        }
    }

    private var panelID: UUID? {
        if case .edit(let panel) = mode { return panel.id }
        return nil
    }
}
