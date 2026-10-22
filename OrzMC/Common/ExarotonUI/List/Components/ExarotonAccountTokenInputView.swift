//
//  ExarotonAccountTokenInputView.swift
//  OrzMC
//
//  Created by joker on 2024/5/21.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonAccountTokenInputView: View {
    @Binding var token: String
    /// 由父视图决定保存后做什么（写 keychain / 重新拉数据 / 关闭 sheet）。
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var isRevealed = false
    @FocusState private var tokenFieldFocused: Bool

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                Text("Input Account Token")
                    .font(.headline)
                Text("Stored in the macOS/iOS keychain and only used for exaroton requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: OrzMCTheme.Spacing.sm) {
                // 单行字段：多行 `TextField(axis: .vertical)` 在 HStack 里与右侧眼睛按钮垂直错位，
                // 显示/隐藏时高度还会跳。令牌本来也不需要换行。
                Group {
                    if isRevealed {
                        TextField("TOKEN", text: $token)
                    } else {
                        SecureField("TOKEN", text: $token)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($tokenFieldFocused)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
#endif

                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide token" : "Show token")
                .accessibilityLabel(isRevealed ? "Hide token" : "Show token")
            }

            HStack(spacing: OrzMCTheme.Spacing.md) {
                ExarotonTradeMarkView()
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedToken.isEmpty)
            }
        }
        .padding(OrzMCTheme.Spacing.lg)
        .frame(minWidth: 320, maxWidth: 460)
        .onAppear { tokenFieldFocused = true }
    }

    /// 显示/隐藏会在 `SecureField` 与 `TextField` 之间换控件，焦点会丢；
    /// 换完后把焦点放回输入框（已输入的内容由父级 binding 保留）。
    private func toggleReveal() {
        isRevealed.toggle()
        Task { @MainActor in
            await Task.yield()
            tokenFieldFocused = true
        }
    }
}

#Preview {
    ExarotonAccountTokenInputView(token: .constant("your_account_token"))
        .padding()
}
