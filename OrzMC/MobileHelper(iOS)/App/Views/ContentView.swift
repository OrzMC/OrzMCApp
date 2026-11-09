//
//  ContentView.swift
//  OrzMC
//
//  Created by joker on 2022/10/24.
//

import SwiftUI

/// iOS 的唯一入口：**服务器管理页**（与 macOS 的「服务器」窗口同一份 `ServersContentView`）。
///
/// 以前是两个并列的 Tab（我的服务器 / 远程托管），每种来源一个页面。但用户的心智模型只有
/// "我的服务器现在怎么样"，"服务器在哪"（自己的机器 / Exaroton / MCSManager 面板）应该是
/// **同一张列表里的分组**——合并后不用来回切，页顶只有一个「添加服务器」菜单。
struct ContentView: View {
    var body: some View {
        ServersContentView()
    }
}

#Preview {
    ContentView()
}
