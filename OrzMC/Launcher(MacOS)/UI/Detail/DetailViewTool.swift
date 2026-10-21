//
//  DetailViewTool.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/5.
//

import SwiftUI

extension View {
    func detailTool() -> some View {
        modifier(DetailToolModifier())
    }
}

struct DetailToolModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            DetailViewTool()
        }
    }
}

/// 详情页工具栏：只保留与本机实例相关的入口。
///
/// 远程托管已经独立成窗口（侧边栏 “Remote Servers”），不再混在这里。
struct DetailViewTool: View {
    var body: some View {
        LinkMenu()
    }
}

#Preview {
    DetailViewTool()
        .padding()
}
