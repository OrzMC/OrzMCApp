//
//  ExarotonContent.swift
//  OrzMC
//
//  Created by joker on 2024/5/22.
//

import SwiftUI

struct ExarotonContent: View {
    @State private var model = ExarotonServerModel()
    var body: some View {
        NavigationStack(path: $model.path) {
            ExarotonServerList().environment(model)
        }
        .alert("Remote Server Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .alert("Remote Server", isPresented: Binding(
            get: { model.statusMessage != nil },
            set: { if !$0 { model.statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.statusMessage = nil }
        } message: {
            Text(verbatim: model.statusMessage ?? "")
        }
    }
}

#Preview {
    ExarotonContent()
}
