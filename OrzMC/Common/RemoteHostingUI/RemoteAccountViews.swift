import OrzMCDesignSystem
import SwiftUI

/// Shared account header; provider-specific menus and contents stay with their provider.
struct RemoteAccountHeader<Actions: View>: View {
    let name: String
    var subtitle: String? = nil
    let isLoading: Bool
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                // 账号/面板是**容器**：比里面的服务器名小一档（服务器才是内容）。
                // 以前三者都是 `.headline`，层级只靠缩进，卡片里看起来"一样重要"。
                Text(verbatim: name).font(.callout.weight(.semibold))
                    .accessibilityIdentifier("remote.accountName")
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(.caption)
                        .foregroundStyle(OrzMCTheme.Palette.metadata)
                }
            }
            Spacer(minLength: OrzMCTheme.Spacing.xs)
            if isLoading { ProgressView().controlSize(.small) }
            actions()
        }
    }
}

struct RemoteAccountEditor<Fields: View>: View {
    let title: String
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        NavigationStack {
            Form { fields() }
                .formStyle(.grouped)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: onSave).disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }
}

/// Both providers use the same name/status layout; long names and large text can wrap the badge.
struct RemoteInstanceHeading: View {
    let name: String
    let statusTitle: String?
    let statusStyle: OrzMCStatusStyle

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                Text(verbatim: name).font(.headline).fixedSize(horizontal: true, vertical: false)
                badge
            }
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                Text(verbatim: name).font(.headline).fixedSize(horizontal: false, vertical: true)
                badge
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let statusTitle { OrzMCStatusBadge(verbatim: statusTitle, style: statusStyle) }
    }
}

struct RemoteProviderHeader: View {
    let name: String
    let systemImage: String
    let count: Int
    let identifier: String
    /// 这一组是否展开（折叠时只显示本行；点左侧箭头或标题切换）。
    var isExpanded = true
    /// 折叠/展开这一组；`nil` = 不提供该交互。
    var onToggle: (() -> Void)? = nil

    var body: some View {
        // 「添加」不再跟在每个供应商标题后面：页顶只有一个添加入口（`AddServerMenu`），
        // 先选服务器类型再填对应表单。这里负责"这是哪家、有几个"，以及折叠/展开。
        HStack(spacing: OrzMCTheme.Spacing.xs) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        // 命中区 18×18：5pt 宽的箭头只有一圈 12×12 的框，指针也很难点中。
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                // iOS 的 borderless 按钮默认用强调色染图标：折叠箭头会变成蓝色（像链接）。
                // 它是**结构控件**，不该抢强调色（2026-11-08 浅色模拟器截图确认）。
                .tint(.secondary)
                .help(isExpanded ? "Collapse this section" : "Expand this section")
                .accessibilityLabel(Text(isExpanded ? "Collapse this section" : "Expand this section"))
                .accessibilityIdentifier("\(identifier).toggle")
            }
            Label {
                // 标识留在 **Text** 上（UI 用例用 `staticTexts[...]` 找它）：
                // 别把它挪到外层容器，那会下发给子元素并覆盖它们自己的 identifier。
                Text(verbatim: name).accessibilityIdentifier(identifier)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            // 分组是**结构标签**：比卡片标题小一档 + 次级色（与主窗口「客户端/服务端」分组一致）。
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            // 点标题也能折叠/展开（与主窗口实例栏的表头一致）。
            .contentShape(Rectangle())
            .onTapGesture { onToggle?() }
            if count > 0 {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
