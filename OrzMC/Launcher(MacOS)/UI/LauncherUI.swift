//
//  LauncherUI.swift
//  OrzMC
//
//  Created by joker on 2022/10/19.
//

import SwiftUI

struct LauncherUI: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            GameView()
                .navigationSplitViewColumnWidth(Constants.sidebarWidth)
        } detail: {
            GameInfoView()
        }
        .navigationSplitViewStyle(.prominentDetail)
        .feedbackToAuthor(email: Constants.feedbackEmail)
        .alert("Operation Failed", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    LauncherUI()
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
        .environment(GameModel())
}
