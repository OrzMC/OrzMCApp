import SwiftUI

/// 表单行：**固定宽度的标签列 + 紧跟的控件**，整体左对齐。
///
/// 为什么不用系统默认样式：macOS 的分组 `Form` 会把标签列撑到大约半行宽，
/// 窗口一宽（1200pt）标签和控件就被拉到卡片两端，看着像"两列没对上"。
/// 固定标签列后，所有行的控件左边缘在同一条竖线上，这就是"精致"的主要来源。
///
/// 用法：在 `Section` 或 `Form` 上 `.labeledContentStyle(.orzMCFieldRow)`；
/// 需要更宽的标签（英文长标签）时用 `.orzMCFieldRow(labelWidth: 128)`。
public struct OrzMCFieldRowStyle: LabeledContentStyle {
    private let labelWidth: CGFloat
    private let spacing: CGFloat

    public init(labelWidth: CGFloat = 96, spacing: CGFloat = 12) {
        self.labelWidth = labelWidth
        self.spacing = spacing
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            configuration.label
                .frame(width: labelWidth, alignment: .leading)
            // 关键：表单里的 `TextField` 会自带「撑满 + 右对齐」的布局，直接放进 HStack 会被推到行尾。
            // 这里显式让它从标签右侧开始、占满剩余宽度；字段**内部**的文字对齐由
            // `.multilineTextAlignment(...)` 决定（数值用 trailing，其余用 leading）。
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public extension LabeledContentStyle where Self == OrzMCFieldRowStyle {
    /// 默认标签列 96pt（中文 3–4 字 / 英文短标签都放得下）。
    static var orzMCFieldRow: OrzMCFieldRowStyle { OrzMCFieldRowStyle() }

    /// 自定义标签列宽度（英文长标签用）。
    static func orzMCFieldRow(labelWidth: CGFloat) -> OrzMCFieldRowStyle {
        OrzMCFieldRowStyle(labelWidth: labelWidth)
    }
}
