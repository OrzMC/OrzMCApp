//
//  ExarotonTradeMarkView.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import SwiftUI

struct ExarotonTradeMarkView: View {
    var body: some View {
        VStack(alignment: .trailing) {
            HStack(alignment: .center) {
                Image("exaroton", bundle: nil)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .offset(y: 3)
                Text(verbatim: "Exaroton")
                    .font(.title)
                    .bold()
            }
            Text("by Aternos")
                .font(.footnote)
        }
    }
}
