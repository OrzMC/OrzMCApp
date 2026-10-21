//
//  LinkMenu.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/5.
//

import SwiftUI

/// 详情页工具栏的「Links」菜单。
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
        }
        .help("Open related links in your browser")
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
