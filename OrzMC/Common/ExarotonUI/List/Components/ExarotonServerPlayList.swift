//
//  ExarotonServerPlayList.swift
//  OrzMC
//
//  Created by joker on 2024/5/21.
//

import SwiftUI

struct ExarotonServerPlayList: View {
    let playlist: [String]
    var body: some View {
        // 外层已经是 Form/List 的 Section：这里不要再套 List（会变成嵌套滚动）。
        ForEach(playlist, id: \.self) { playerName in
            Text(playerName)
        }
    }
}
