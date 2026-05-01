//
//  LinkMenu.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/5.
//

import SwiftUI

struct LinkMenu: View {
    let items: [LinkInfo] = LinkMenu.allLinkItems
    @Binding var path: NavigationPath
    var body: some View {
        Menu {
            ForEach(items) { item in
                switch item.type {
                case .testServer, .onlineServer:
                    Link(destination: URL(string: item.url)!) {
                        Label(item.name, systemImage: item.icon)
                    }
                default:
                    Button(item.name, systemImage: item.icon) {
                        path.append(item)
                    }
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "link")
        }
    }
}

extension LinkMenu {
    struct LinkInfo: Identifiable, Hashable {
        var id: String { url }
        
        let url: String
        let icon: String
        
        enum LinkType {
            case home
            case papermc
            case gameExt
            case testServer
            case onlineServer
        }
        let type: LinkType
        
        let name: String
    }
    static let allLinkItems: [LinkInfo] = [
        .init(url: "https://orzmc.jokerhub.cn", icon: "house", type: .home, name: "Home"),
        .init(url: "https://papermc.io/", icon: "paperplane", type: .papermc, name: "PaperMC"),
        .init(url: "https://hangar.papermc.io/", icon: "powerplug", type: .gameExt, name: "Hangar"),
        .init(url: "https://aternos.org/server/", icon: "testtube.2", type: .testServer, name: "Aternos"),
        .init(url: "https://exaroton.com/server", icon: "server.rack", type: .onlineServer, name: "Exaroton"),
    ]
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        LinkMenu(path: $path)
    }
}
