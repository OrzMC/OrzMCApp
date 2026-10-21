//
//  ExarotonServerList.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import OrzMCDesignSystem
import SwiftUI

/// Exaroton 远程服务器列表（macOS / iOS 共用）。
///
/// 交互统一：
/// - 行用 `NavigationLink(value:)`（而不是 `onTapGesture`）：有系统高亮、键盘导航、
///   辅助功能“按钮”语义和返回手势；
/// - 空状态用 `ContentUnavailableView`，并直接给出“添加 Token”的动作；
/// - 加载用条件渲染的 `ProgressView`，不再用 `.opacity(0)`（透明但仍然拦截点击）。
struct ExarotonServerList: View {
    @Environment(ExarotonServerModel.self) private var model

    @State private var token: String = ""
    @State private var isLoading = false
    @State private var showTokenInput = false

    private var isEmpty: Bool {
        model.servers.isEmpty && model.creditPools.isEmpty
    }

    var body: some View {
        List {
            if !model.servers.isEmpty {
                Section {
                    ForEach(model.servers, id: \.id) { server in
                        NavigationLink(value: server) {
                            ExarotonServerView(server: server)
                        }
                    }
                } header: {
                    HStack {
                        Label("Servers", systemImage: "server.rack")
                        Spacer()
                        Text("\(model.servers.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !model.creditPools.isEmpty {
                Section {
                    ForEach(model.creditPools) { creditPool in
                        NavigationLink(value: creditPool) {
                            ExarotonCreditPoolView(creditPool: creditPool)
                        }
                    }
                } header: {
                    HStack {
                        Label("Credit Pools", systemImage: "bubbles.and.sparkles")
                        Spacer()
                        Text("\(model.creditPools.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
#if os(macOS)
        .listStyle(.inset)
#endif
        .navigationTitle("Exaroton")
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(OrzMCTheme.Spacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
            } else if isEmpty {
                ContentUnavailableView {
                    Label("No remote servers", systemImage: "server.rack")
                } description: {
                    Text("Sign in with your exaroton account token to manage remote servers here.")
                } actions: {
                    Button("Add Account Token…") {
                        showTokenInput = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .refreshable {
            await fetchData()
        }
        .toolbar {
            ToolbarItemGroup {
#if os(macOS)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await fetchDataWithLoading() }
                }
                .keyboardShortcut(.init(.init("r")), modifiers: .command)
                .help("Reload remote servers")
#endif
                Button("Account", systemImage: "key") {
                    token = model.token
                    showTokenInput = true
                }
                .help("Change exaroton account token")
            }
        }
        .sheet(isPresented: $showTokenInput) {
            ExarotonAccountTokenInputView(
                token: $token,
                onSave: saveToken,
                onCancel: { showTokenInput = false }
            )
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(320)])
            .presentationCornerRadius(OrzMCTheme.Radius.lg)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
            .interactiveDismissDisabled(isLoading)
        }
        .task {
            token = model.token
            if model.token.isEmpty {
                showTokenInput = true
            } else {
                await fetchDataWithLoading()
            }
        }
        .navigationDestination(for: ExarotonServer.self) { server in
            ExarotonServerDetail(server: server).environment(model)
        }
        .navigationDestination(for: ExarotonCreditPool.self) { creditPool in
            ExarotonCreditPoolDetail(creditPool: creditPool).environment(model)
        }
    }
}

extension ExarotonServerList {
    private func saveToken() {
        let validToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validToken.isEmpty else { return }
        model.token = validToken
        showTokenInput = false
        Task { await fetchDataWithLoading() }
    }

    func fetchDataWithLoading() async {
        isLoading = true
        await fetchData()
        isLoading = false
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
