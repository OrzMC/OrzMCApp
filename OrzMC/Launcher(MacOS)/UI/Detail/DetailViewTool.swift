//
//  DetailViewTool.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/5.
//

import SwiftUI

extension View {
    func detailTool(model: Binding<ExarotonServerModel>) -> some View {
        let detailToolModifier = DetailToolModifier(model: model)
        return self.modifier(detailToolModifier)
    }
}

struct DetailToolModifier: ViewModifier {
    let model: Binding<ExarotonServerModel>
    func body(content: Content) -> some View {
        content.toolbar {
            DetailViewTool(model: model)
        }
    }
}

struct DetailViewTool: View {
    enum ToolItem: Int, Identifiable, CaseIterable {
        case exaroton
        case links
        var id: Int { self.rawValue }
    }
    @Binding var model: ExarotonServerModel
    var body: some View {
        ForEach(ToolItem.allCases) { item in
            switch item {
            case .exaroton:
                Button("Remote Server", systemImage: "gamecontroller") {
                    model.path.append(ToolItem.exaroton)
                }
                .keyboardShortcut(.init(.init("s")), modifiers: .command)
            case .links:
                LinkMenu(path: $model.path)
            }
        }
    }
}

#Preview {
    @Previewable @State var model = ExarotonServerModel()
    DetailViewTool(model: $model)
}
