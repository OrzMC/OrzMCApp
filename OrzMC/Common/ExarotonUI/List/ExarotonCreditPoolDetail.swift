//
//  ExarotonCreditPoolDetail.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonCreditPoolDetail: View {
    @Environment(ExarotonServerModel.self) var model
    @State private var creditPool: ExarotonCreditPool
    @State private var members: [ExarotonCreditMember]?
    @State private var servers: [ExarotonServer]?
    @State private var isLoading = false

    init(creditPool: ExarotonCreditPool) {
        _creditPool = State(initialValue: creditPool)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: OrzMCTheme.Spacing.sm) {
                    ExarotonCreditView(credits: creditPool.credits, style: .large)

                    if let name = creditPool.name {
                        Text(name)
                            .font(.headline)
                    }
                    if let id = creditPool.id {
                        Text(id)
                            .font(OrzMCTheme.Typography.code)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OrzMCTheme.Spacing.sm)
                .listRowSeparator(.hidden)
            }

            if let members {
                Section {
                    ForEach(members) { member in
                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Text(member.name ?? "—")
                                .lineLimit(1)
                            Spacer(minLength: OrzMCTheme.Spacing.sm)
                            ExarotonCreditView(credits: member.credits)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("Members", systemImage: "person.2")
                }
            }

            if let servers, !servers.isEmpty {
                Section {
                    ForEach(servers) { server in
                        NavigationLink(value: server) {
                            ExarotonServerView(
                                server: server,
                                status: model.effectiveStatus(for: server)
                            )
                        }
                    }
                } header: {
                    Label("Servers", systemImage: "server.rack")
                }
            }
        }
        .task {
            await fetchDataWithLoading()
        }
        .navigationTitle(creditPool.name ?? String(localized: "Credit Pool Detail"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(OrzMCTheme.Spacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
            }
        }
        .refreshable {
            await fetchData()
        }
        .toolbar {
#if os(macOS)
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task {
                    await fetchDataWithLoading()
                }
            }
            .keyboardShortcut(.init(.init("r")), modifiers: .command)
#endif
        }
    }

    func fetchDataWithLoading() async {
        isLoading = true
        await fetchData()
        isLoading = false
    }

    func fetchData() async {
        let info = await model.fetchCreditPoolInfo(creditPool)
        guard let info
        else {

            return
        }
        let (pool, members, servers) = info
        if let pool {
            self.creditPool = pool
        }
        self.members = members
        self.servers = servers
    }
}
