import SwiftUI

/// 控制台 / 日志面板的统一外观。
///
/// 关键点：用 `Color.primary` 的半透明而不是 `Color.black` / `Color.white`，
/// 这样浅色模式是浅灰底、深色模式是浅白底，文字继续用 `.primary`，两种模式都有对比度；
/// 同时跟随系统“提高对比度”设置，不再出现 Exaroton 控制台那种“黑板 + 8pt 白字”。
public struct ConsoleSurface: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = OrzMCTheme.Radius.md) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                OrzMCTheme.Palette.consoleBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OrzMCTheme.Palette.consoleBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    /// 给日志/终端类面板套上统一底色与边框。
    func consoleSurface(cornerRadius: CGFloat = OrzMCTheme.Radius.md) -> some View {
        modifier(ConsoleSurface(cornerRadius: cornerRadius))
    }
}
