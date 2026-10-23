//
//  SidebarSearchBar.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 侧边栏顶部一行：**搜索 + 只看正式版 + 刷新**。
///
/// 三个控件同处一行、后两个是单图标按钮，尽量少占垂直空间；
/// 过滤/刷新作用于下面的列表，所以留在列表自己的顶部（不再挂到窗口工具栏）。
struct SidebarSearchBar: View {
    @Binding var searchText: String
    @Binding var releaseOnly: Bool
    let isLoading: Bool
    /// 搜索框焦点（由 `GameView` 的 ⌘F 控制；Esc/回车交还给列表）。
    var focused: FocusState<Bool>.Binding
    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            searchField
            filterToggle
            reloadButton
        }
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Filter a version", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .labelsHidden()
                .focused(focused)
                // 回车/退出都算"用完了"：交还焦点，方向键立刻回到版本列表。
                .onSubmit { focused.wrappedValue = false }
                .onExitCommand {
                    searchText = ""
                    focused.wrappedValue = false
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(OrzMCTheme.Palette.subtleFill, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
    }

    private var filterToggle: some View {
        Toggle(isOn: $releaseOnly) {
            Label("Releases only", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.button)
        .frame(width: 34, height: 30)
        .help("Show release versions only")
        .accessibilityLabel("Show release versions only")
    }

    private var reloadButton: some View {
        Button(action: onReload) {
            Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .frame(width: 30, height: 30)
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .opacity(isLoading ? 0.45 : 1)
        .disabled(isLoading)
        .help("Refresh version list")
        .accessibilityLabel("Refresh version list")
    }
}

#Preview {
    @Previewable @State var searchText = ""
    @Previewable @State var releaseOnly = true
    SidebarSearchBar(
        searchText: $searchText,
        releaseOnly: $releaseOnly,
        isLoading: false,
        focused: FocusState<Bool>().projectedValue
    ) {}
        .frame(width: Constants.sidebarWidth)
}
