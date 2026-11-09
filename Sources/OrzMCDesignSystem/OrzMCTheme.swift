import SwiftUI

/// 全局设计令牌（颜色 / 间距 / 圆角 / 字体）。
///
/// 设计原则：
/// - **只用系统语义色**：`Color.primary` / `.secondary` / `.accentColor` / `.green` / `.orange` / `.red`
///   会自动跟随浅色/深色、提高对比度（Increase Contrast）与不同平台（macOS / iOS）。
///   不要在这里写 `Color(red:green:blue:)`，也不要写死 `Color.black` / `Color.white`。
/// - 颜色只做**辅助信息**，状态永远同时有文字（色盲 / 灰度屏也能读懂）。
/// - 间距用 4 的倍数，圆角只保留三档，避免每个视图各写一套。
///
/// `Sources/*` 里不允许 `import AppKit` / `import UIKit`，因此这里只用 SwiftUI 的
/// 跨平台语义色；平台差异由 SwiftUI 自身解析。
public enum OrzMCTheme {

    // MARK: - 间距

    public enum Spacing {
        /// 2pt：紧贴的文字/图标。
        public static let hairline: CGFloat = 2
        /// 4pt：同一行内的元素。
        public static let xs: CGFloat = 4
        /// 8pt：控件的行内间距。
        public static let sm: CGFloat = 8
        /// 12pt：内容块之间。
        public static let md: CGFloat = 12
        /// 16pt：页面/面板内边距。
        public static let lg: CGFloat = 16
        /// 24pt：大区块之间。
        public static let xl: CGFloat = 24
    }

    // MARK: - 圆角

    public enum Radius {
        /// 6pt：小标签、日志块。
        public static let sm: CGFloat = 6
        /// 10pt：面板、卡片。
        public static let md: CGFloat = 10
        /// 14pt：大面板。
        public static let lg: CGFloat = 14
    }

    // MARK: - 字体

    public enum Typography {
        /// 控制台正文（等宽，跟随系统字号）。
        /// `.caption` 在 macOS 上约 10pt——日志是主要阅读面，用 `.subheadline` 更接近终端字号。
        public static let console = Font.system(.subheadline, design: .monospaced)
        /// 控制台输入（等宽，正文大小）。
        public static let consoleInput = Font.system(.body, design: .monospaced)
        /// 路径 / ID 等等宽文本。
        public static let code = Font.system(.caption, design: .monospaced)
        /// 版本号等需要纵向对齐的数字。
        public static let numeric = Font.body.monospacedDigit()
    }

    // MARK: - 语义色

    /// 语义色板。**不要**直接用 `.green` / `.red` 表达业务含义，经过这里，
    /// 以后换配色（例如品牌色、色盲友好色）只改一处。
    public enum Palette {
        /// 品牌/强调色（跟随系统 AccentColor，用户可在系统设置里改）。
        public static let accent = Color.accentColor
        /// 运行中 / 成功 / 就绪。
        public static let success = Color.green
        /// 进行中 / 需要注意。
        public static let warning = Color.orange
        /// 错误 / 破坏性操作。
        public static let danger = Color.red
        /// 未运行 / 未知 / 中性。
        public static let idle = Color.secondary
        /// 卡片上的图标按钮：接近正文强度（不是 `.secondary` 那种"灰"）。
        ///
        /// 为什么不用 `.secondary`：面板底是半透明/玻璃层，`secondary` 的灰在深色下合成后
        /// 只有约 3.2:1，图标在卡片上"像禁用"；0.72 实测仍有 180/255 的灰，
        /// 维护者两次反馈"一直灰色、像不可点击"（2026-11-08）。0.85 在深/浅外观下都 ≥10:1，
        /// 与 disabled（0.35）拉开足够差距，也不会像纯白那样抢标题。
        public static let control = Color.primary.opacity(0.85)
        /// 卡片里的"次要但重要"信息（地址、版本/玩家/延迟、MOTD）。
        ///
        /// 比 `.secondary` 强一档（11pt 下 `.secondary` 实测 3.2:1，低于 4.5:1）；
        /// 又比正文弱，保证标题仍然是第一眼看到的东西。
        public static let metadata = Color.primary.opacity(0.65)

        /// 轻量填充（标签、次级按钮背景）。
        public static let subtleFill = Color.secondary.opacity(0.12)
        /// 控制台/日志背景：用 primary 的半透明，浅色下是浅灰、深色下是浅白，两种模式都可见。
        public static let consoleBackground = Color.primary.opacity(0.06)
        /// 控制台/日志边框。
        public static let consoleBorder = Color.primary.opacity(0.10)
        /// 分割线（比系统 Divider 略明显一点，用于按钮分组）。
        public static let separator = Color.secondary.opacity(0.25)
        /// 面板填充（macOS 26 以下作为液态玻璃的回退外观）。
        public static let panelFill = Color.primary.opacity(0.045)
        /// 面板描边。
        public static let panelBorder = Color.primary.opacity(0.08)
        /// 分段/模式按钮的选中底色（跟随系统强调色，亮暗都成立）。
        public static let selectionFill = Color.accentColor.opacity(0.22)
        /// 中性选中底：只表达"这一档生效"，不带品牌色。
        ///
        /// 用在"全部折叠/全部展开"这类**模式**控件上：强调色已经在状态徽章/主操作上表达含义，
        /// 同一屏再用强调色表达"选中"，同一个绿色就有两种意思了（HIG Color：别让同色多义）。
        public static let selectionNeutral = Color.primary.opacity(0.14)
        /// 面板上的可点控件（下拉菜单胶囊、输入框）底色：比 `subtleFill` 略重，
        /// 亮色面板（primary 4.5%）上也能看出"这是一个控件"。
        public static let controlFill = Color.primary.opacity(0.08)
    }
}
