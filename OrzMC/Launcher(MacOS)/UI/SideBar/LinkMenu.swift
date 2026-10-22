//
//  LinkMenu.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/5.
//

import SwiftUI

/// 窗口工具栏的「外部链接」菜单（与“远程服务器”入口、侧边栏开关同一排）。
///
/// 这些链接（官网 / PaperMC / Hangar / Aternos / Exaroton）**与具体版本无关**，
/// 所以放在窗口级工具栏随应用常驻，而不是挂在某个版本的详情页工具栏上 ——
/// 详情页只负责“当前版本”的启动与实例管理。
///
/// 统一用系统 `Link` 打开**默认浏览器**：
/// - 系统组件自带正确的外观、键盘可达性和辅助功能标签；
/// - 不会把网页塞进启动器的 `NavigationStack`（以前用 SwiftUIX 的 `Web`，进网页后
///   工具栏/返回语义都变得像浏览器，且要多维护一个 WKWebView 包装）。
struct LinkMenu: View {
    private let items: [LinkInfo] = LinkMenu.allLinkItems

    var body: some View {
        Menu {
            ForEach(items) { item in
                if let url = URL(string: item.url) {
                    Link(destination: url) {
                        Label(item.name, systemImage: item.icon)
                    }
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Label("Links", systemImage: "link")
                .labelStyle(.iconOnly)
        }
        // 不显示下拉箭头：与相邻的“远程服务器”“侧边栏开关”保持同样的圆形按钮轮廓。
        .menuIndicator(.hidden)
        .help("Open related links in your browser")
        .accessibilityLabel("Links")
    }
}

extension LinkMenu {
    struct LinkInfo: Identifiable, Hashable {
        var id: String { url }

        let url: String
        let icon: String
        let name: String
    }

    static let allLinkItems: [LinkInfo] = [
        .init(url: "https://orzmc.jokerhub.cn", icon: "house", name: "Home"),
        .init(url: "https://papermc.io/", icon: "paperplane", name: "PaperMC"),
        .init(url: "https://hangar.papermc.io/", icon: "powerplug", name: "Hangar"),
        .init(url: "https://aternos.org/server/", icon: "testtube.2", name: "Aternos"),
        .init(url: "https://exaroton.com/server", icon: "server.rack", name: "Exaroton"),
    ]
}

#Preview {
    LinkMenu()
        .padding()
}
