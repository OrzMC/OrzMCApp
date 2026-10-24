//
//  ExarotonCopyableText.swift
//  OrzMC
//
//  Created by joker on 9/6/24.
//

import OrzMCDesignSystem
import SwiftUI

/// 可复制的地址/ID（复制后短暂显示「已复制」）。
///
/// 三个细节：
/// - 复制状态是**一个**枚举，而不是两个互相追赶的布尔（以前 `isTapped` / `copyed` 会打架）；
/// - 用 `Task.sleep(for:)` 而不是 `DispatchQueue.main.asyncAfter`（视图消失时随之取消）；
/// - 文案走本地化表（`Copy` / `Copied`）。
struct ExarotonCopyableText: View {

    private enum CopyState {
        case idle
        case copied
        case failed
    }

    private let content: String
    private let canCopy: Bool

    @State private var state: CopyState = .idle
    @State private var resetTask: Task<Void, Never>?

    init(_ content: String, canCopy: Bool = false) {
        self.content = content
        self.canCopy = canCopy
    }

    private var symbolName: String {
        switch state {
        case .idle: return "document.on.clipboard"
        case .copied: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .idle: return OrzMCTheme.Palette.accent
        case .copied: return OrzMCTheme.Palette.success
        case .failed: return OrzMCTheme.Palette.danger
        }
    }

    private var label: LocalizedStringKey {
        switch state {
        case .idle: return "Copy"
        case .copied: return "Copied"
        case .failed: return "Copy failed"
        }
    }

    var body: some View {
        HStack {
            Text(verbatim: content)
                .textSelection(.enabled)
                .fontWeight(.medium)

            Spacer()

            if canCopy {
                Button {
                    copy()
                } label: {
                    Image(systemName: symbolName)
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.borderless)
                .help(label)
                .accessibilityLabel(label)
            }
        }
        .onDisappear { resetTask?.cancel() }
    }

    private func copy() {
        resetTask?.cancel()
        let copied = content.copyToPasteboard()
        state = copied ? .copied : .failed
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            state = .idle
        }
    }
}

#Preview {
    ExarotonCopyableText("Content To Be Copied!", canCopy: true)
}
