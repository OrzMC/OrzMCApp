//
//  ExarotonCopyableText.swift
//  OrzMC
//
//  Created by joker on 9/6/24.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonCopyableText: View {
    
    private let content: String
    private let canCopy: Bool
    
    @State private var copyed: Bool = false
    @State private var isTapped: Bool = false
    
    init(_ content: String, canCopy: Bool = false) {
        self.content = content
        self.canCopy = canCopy
    }

    var body: some View {
        HStack {
            Text("\(content)")
            
            Spacer()
            
            if canCopy {
                Button {
                    isTapped = true
                    copyed = content.copyToPasteboard()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isTapped = false
                        copyed = false
                    }
                } label: {
                    Image(systemName: isTapped ? "checkmark.circle" : "document.on.clipboard")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copyed ? OrzMCTheme.Palette.success : OrzMCTheme.Palette.accent)
                }
                .buttonStyle(.borderless)
                .help(copyed ? "Copied" : "Copy")
                .accessibilityLabel(copyed ? "Copied" : "Copy")
            }
        }
    }
}

#Preview {
    ExarotonCopyableText("Content To Be Copyed!")
}
