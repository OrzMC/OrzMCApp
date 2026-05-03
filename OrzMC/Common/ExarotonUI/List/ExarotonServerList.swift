//
//  ExarotonServerList.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import SwiftUI

struct ExarotonServerList: View {
    @Environment(ExarotonServerModel.self) var model
    @State private var token: String = ""
    @State private var isLoading = false
    @State private var showTokenInput = false
    var body: some View {
        List() {
            if !model.servers.isEmpty {
                Section("Servers") {
                    ForEach(model.servers, id: \.id) { server in
                        ExarotonServerView(server: server)
                            .onTapGesture {
                                model.path.append(server)
                            }
                    }
                }
            }
            if !model.creditPools.isEmpty {
                Section("Credit Pools") {
                    ForEach(model.creditPools) { creditPool in
                        ExarotonCreditPoolView(creditPool: creditPool)
                            .onTapGesture {
                                model.path.append(creditPool)
                            }
                    }
                }
            }
        }
#if os(macOS)
        .listStyle(.inset)
#endif
        .navigationTitle("Exaroton")
        .overlay {
            ProgressView()
                .controlSize(.extraLarge)
                .progressViewStyle(.circular)
                .opacity(isLoading ? 1 : 0)
        }
        .refreshable {
            await fetchData()
        }
        .toolbar {
            ToolbarItemGroup {
#if os(macOS)
                Button("Refresh Page", systemImage: "arrow.circlepath") {
                    Task {
                        await fetchDataWithLoading()
                    }
                }
                .keyboardShortcut(.init(.init("r")), modifiers: .command)
#endif
                Button("Settings", systemImage: "gear") {
                    showTokenInput.toggle()
                }
                .keyboardShortcut(.init(.init("t")), modifiers: .command)
            }
        }
        .sheet(isPresented: $showTokenInput) {
            if !token.isEmpty {
                model.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await fetchDataWithLoading()
                }
            }
        } content: {
            ExarotonAccountTokenInputView(token: $token)
                .onSubmit {
                    showTokenInput = false
                }
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(250)])
                .presentationCornerRadius(10)
                .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
        }
        .task {
            token = model.token
            if model.token.isEmpty {
                showTokenInput = true
            } else {
                await fetchDataWithLoading()
            }
        }
        .navigationDestination(for: ExarotonServer.self, destination: { server in
            ExarotonServerDetail(server: server).environment(model)
        })
        .navigationDestination(for: ExarotonCreditPool.self, destination: { creditPool in
            ExarotonCreditPoolDetail(creditPool: creditPool).environment(model)
        })
    }
}

extension ExarotonServerList {
    func fetchDataWithLoading() async {
        self.isLoading = true
        await fetchData()
        self.isLoading = false
    }
    func fetchData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await model.fetchServers()
            }
            group.addTask {
                await model.fetchCreditPools()
            }
        }
    }
}


#Preview {
    ExarotonServerList()
        .environment(ExarotonServerModel())
}
