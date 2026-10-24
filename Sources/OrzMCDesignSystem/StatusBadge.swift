import SwiftUI

/// 状态的语义分类。颜色只做辅助，真正的信息在文字里。
public enum OrzMCStatusStyle: Sendable, Equatable {
    /// 未运行 / 未知 / 中性。
    case idle
    /// 运行中 / 就绪。
    case running
    /// 启动中 / 停止中 / 重启中（进行态）。
    case busy
    /// 需要注意（例如 CLI 记录损坏、JRE 缺失）。
    case warning
    /// 出错。
    case error

    public var tint: Color {
        switch self {
        case .idle: return OrzMCTheme.Palette.idle
        case .running: return OrzMCTheme.Palette.success
        case .busy: return OrzMCTheme.Palette.warning
        case .warning: return OrzMCTheme.Palette.warning
        case .error: return OrzMCTheme.Palette.danger
        }
    }

    public var symbolName: String {
        switch self {
        case .idle: return "circle"
        case .running: return "checkmark.circle.fill"
        case .busy: return "arrow.triangle.2.circlepath"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// 统一状态胶囊：小图标 + 文字 + 语义色背景。
///
/// 之前每个视图各写一套（详情页、控制台、Java 状态、Exaroton），颜色和圆角都不一致；
/// 现在只从这里出。系统组件 `.badge` 只支持数字/短文本，所以保留这个轻量自定义视图。
///
/// 支持两种文案：静态文案走 `Localizable.xcstrings`，运行时文案（来自模型/引擎）原样显示。
public struct OrzMCStatusBadge: View {
    private enum Content {
        case localized(LocalizedStringKey)
        case verbatim(String)
    }

    private let content: Content
    private let style: OrzMCStatusStyle

    public init(_ text: LocalizedStringKey, style: OrzMCStatusStyle) {
        self.content = .localized(text)
        self.style = style
    }

    public init(verbatim text: String, style: OrzMCStatusStyle) {
        self.content = .verbatim(text)
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 6) {
            // 用 SF Symbol 而不是 Circle：进行态可以复用同一个视觉语言（箭头/对勾/感叹号）。
            // 进行态：让**徽章里的图标**一直转（用显式 rotationEffect + repeatForever；
            // `symbolEffect(.rotate)` 在徽章文案更新导致局部重绘时会停下——真机反馈"转一会儿不转了"）。
            SpinningStatusIcon(
                systemName: style == .idle ? "circle.fill" : style.symbolName,
                isSpinning: style == .busy,
                tint: style.tint
            )
            .accessibilityHidden(true)

            textView
                .font(.caption)
                .foregroundStyle(.primary)
                // 不锁单行：中文长状态（「正在重启，请稍候…」）+ 无障碍字号会被截成省略号。
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(style.tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var textView: some View {
        switch content {
        case .localized(let key):
            Text(key)
        case .verbatim(let text):
            Text(verbatim: text)
        }
    }
}

/// 状态徽章里的图标：进行态持续旋转。
///
/// 为什么不用 `symbolEffect(.rotate)`：那个效果依赖"符号被重新插入"，徽章文案更新引起局部重绘时
/// 动画会停住（真机反馈"转一下就停了"）。这里用 `rotationEffect` + `repeatForever`，
/// 与重绘无关，直到 `isSpinning` 变回 false 才停。
private struct SpinningStatusIcon: View {
    let systemName: String
    let isSpinning: Bool
    let tint: Color

    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: systemName)
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(angle))
            .onAppear { angle = isSpinning ? 360 : 0 }
            .onChange(of: isSpinning) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
                }
            }
    }
}

/// 轻量标签（`local` / 版本类型 / 渠道 / 更新数）。
///
/// 与状态徽标分开：标签表达“分类”，不表达“状态”，因此默认用次级色描边而不是填充色块，
/// 在侧边栏选中行（系统会反色）里也不会出现“同色覆盖同色”的问题。
public struct OrzMCTag: View {
    /// 运行时文案（例如已装核心名）走 `String`；静态文案用 `LocalizedStringKey` 自动进本地化表。
    private enum Content {
        case verbatim(String)
        case localized(LocalizedStringKey)
    }

    private let content: Content
    private let tint: Color?

    public init(_ text: String, tint: Color? = nil) {
        self.content = .verbatim(text)
        self.tint = tint
    }

    public init(_ key: LocalizedStringKey, tint: Color? = nil) {
        self.content = .localized(key)
        self.tint = tint
    }

    private var textView: Text {
        switch content {
        case .verbatim(let text): return Text(verbatim: text)
        case .localized(let key): return Text(key)
        }
    }

    public var body: some View {
        let resolved = tint ?? OrzMCTheme.Palette.idle
        textView
            // `.caption2` 在 macOS 上只有 ~9pt（design 规则里明确「慎用」）：标签正文用 `.caption`。
            .font(.caption.weight(.medium))
            // 标签是"一个整体"，不许折行：小屏（iPhone SE）上折行会让标签变成两行方框，
            // 卡片高度跟着跳，读起来像排版错乱。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(resolved))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                Capsule().strokeBorder(resolved.opacity(0.5), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

/// 统一的提示条：错误 / 警告 / 说明。
///
/// 之前错误文案散落在各处（有的红色、有的橙色、有的没有图标），且不可选中；
/// 这里统一带图标、可选中文本，方便用户把错误码复制给维护者。
/// 静态文案走本地化表；运行时错误用 `init(verbatim:role:)`。
public struct OrzMCBanner: View {
    public enum Role: Sendable {
        case info
        case warning
        case error

        var tint: Color {
            switch self {
            case .info: return OrzMCTheme.Palette.idle
            case .warning: return OrzMCTheme.Palette.warning
            case .error: return OrzMCTheme.Palette.danger
            }
        }

        var symbolName: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    private enum Content {
        case localized(LocalizedStringKey)
        case verbatim(String)
    }

    private let role: Role
    private let content: Content

    public init(_ text: LocalizedStringKey, role: Role) {
        self.role = role
        self.content = .localized(text)
    }

    public init(verbatim text: String, role: Role) {
        self.role = role
        self.content = .verbatim(text)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: role.symbolName)
                .font(.caption)
                .foregroundStyle(role.tint)
                .accessibilityHidden(true)
            textView
                .font(.caption)
                // 错误/警告要能在「提高对比度」和灰度下读清：正文用主色；
                // 只有纯说明（info）用次要色，避免和正文抢注意力。
                .foregroundStyle(role == .info ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(textView)
    }

    private var textView: Text {
        switch content {
        case .localized(let key):
            return Text(key)
        case .verbatim(let text):
            return Text(verbatim: text)
        }
    }
}
