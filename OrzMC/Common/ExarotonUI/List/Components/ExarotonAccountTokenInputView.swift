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
                Group {
                    if isRevealed {
                        TextField("TOKEN", text: $token, axis: .vertical)
                    } else {
                        SecureField("TOKEN", text: $token)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .lineLimit(3, reservesSpace: false)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
#endif

                Button {
                    isRevealed.toggle()
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
    }
}

#Preview {
    ExarotonAccountTokenInputView(token: .constant("your_account_token"))
        .padding()
}
