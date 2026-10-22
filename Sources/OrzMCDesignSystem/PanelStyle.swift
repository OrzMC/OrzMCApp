import SwiftUI

/// 详情页/设置页的面板外观。
///
/// macOS 26 起用系统 **Liquid Glass**（`glassEffect`），更老的系统退回
/// 「半透明填充 + 细描边」的等效观感（同一个圆角、同一套间距）。
///
/// 用法：`content.padding(16).orzMCPanel()`。
public struct OrzMCPanel: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        // 同一份代码编两个平台：两边都要 26.0 才有 `glassEffect`。
        if #available(macOS 26.0, iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    OrzMCTheme.Palette.panelFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(OrzMCTheme.Palette.panelBorder, lineWidth: 1)
                )
        }
    }
}

public extension View {
    /// 统一面板外观（macOS 26+ 为液态玻璃）。
    func orzMCPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(OrzMCPanel(cornerRadius: cornerRadius))
    }
}
