import SwiftUI

/// 让"整卡可点"的元素在鼠标悬停时给出反馈。
///
/// `NavigationLink` / `Button` 用 `.buttonStyle(.plain)` 时系统不给高亮，
/// 用户看不出"这块能点"；而系统默认按钮样式又会把卡片内容染成强调色。
/// 这里只加一层很淡的描边 + 轻微背景，保持卡片原样。
private struct PointerHoverStyle: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OrzMCTheme.Palette.accent.opacity(isHovering ? 0.06 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        OrzMCTheme.Palette.accent.opacity(isHovering ? 0.35 : 0),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

public extension View {
    /// 鼠标悬停时给"可点卡片"一点反馈（不改变卡片本身的底色/尺寸）。
    func orzMCPointerHover() -> some View {
        modifier(PointerHoverStyle())
    }
}
