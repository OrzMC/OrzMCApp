//
//  GameInfoView.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import SwiftUI
import SwiftUIX

struct GameInfoView: View {
    @State private var model = ExarotonServerModel()
    var body: some View {
        NavigationStack(path: $model.path) { BasicInfo() }
            .navigationDestination(for: DetailViewTool.ToolItem.self, destination: handleTool)
            .navigationDestination(for: LinkMenu.LinkInfo.self, destination: handleLink)
            .detailTool(model: $model)
            .alert("Remote Server Error", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Remote Server", isPresented: Binding(
                get: { model.statusMessage != nil },
                set: { if !$0 { model.statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    model.statusMessage = nil
                }
            } message: {
                Text(model.statusMessage ?? "")
            }
    }
    @ViewBuilder
    func handleTool(_ tool: DetailViewTool.ToolItem) -> some View {
        switch tool {
        case .exaroton:
            ExarotonServerList().environment(model)
        default:
            EmptyView()
        }
    }
    @ViewBuilder
    func handleLink(_ link: LinkMenu.LinkInfo) -> some View {
        if let linkURL = URL(string: link.url) {
            Web(url: linkURL)
        }
        else{
            if link.url.isEmpty {
                Text("URL为空")
            } else {
                Text("URL格式错误：\(link.url)")
            }
        }
    }
}

#Preview {
    GameInfoView()
        .frame(width: Constants.minWidth - Constants.sidebarWidth, height: Constants.minHeight)
        .environment(GameModel())
}
