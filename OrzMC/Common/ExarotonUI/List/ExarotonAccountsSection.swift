import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

/// **exaroton** 分组：图标标题 + 每个账号一张卡（实例 + 额度池）。
///
/// 结构走 `RemoteProviderSection` / `RemoteAccountCard` / `RemoteAccountMenu`（与 MCSM 同一套骨架），
/// 这里只保留 exaroton 特有的部分：账号凭据编辑、实例卡、额度池。
struct ExarotonAccountsSection: View {
    /// 页顶「添加账号」选中了 exaroton 时，这里弹出对应的表单（选完即清）。
    @Binding var addRequest: ProviderKind?
    @Environment(ExarotonAccountsModel.self) private var accounts
    @State private var editing: ExarotonAccount?
    @State private var showingEditor = false
    @State private var name = ""
    @State private var token = ""

    private var instanceCount: Int {
        accounts.models.values.reduce(0) { $0 + $1.servers.count }
    }


    var body: some View {
        RemoteProviderSection(
            name: "exaroton",
            systemImage: "cloud",
            count: instanceCount,
            identifier: "exaroton.section"
        ) {
            ForEach(accounts.accounts) { account in
                if let model = accounts.models[account.id] {
                    accountCard(account, model: model)
                }
            }
            if let error = accounts.errorMessage {
                RemoteInlineError(message: error)
            }
        }
        .sheet(isPresented: $showingEditor) { editorSheet }
        .onChange(of: addRequest) { _, request in
            guard request == .exaroton else { return }
            beginAdding()
            addRequest = nil
        }
    }

    // MARK: - 组件

    private func accountCard(_ account: ExarotonAccount, model: ExarotonServerModel) -> some View {
        RemoteAccountCard(name: account.displayName, isLoading: model.isLoadingList) {
            RemoteAccountMenu(
                onRefresh: { Task { await model.reloadList() } },
                onEdit: {
                    editing = account
                    name = account.label
                    token = ""
                    showingEditor = true
                },
                onRemove: { accounts.remove(account.id) }
            )
        } content: {
            ExarotonServerList()
                .environment(model)
                .id(ObjectIdentifier(model))
        }
        .task(id: ObjectIdentifier(model)) { await accounts.resolveDefaultName(for: account.id) }
    }

    private var editorSheet: some View {
        RemoteAccountEditor(
            title: editing == nil ? String(localized: "Add Account") : String(localized: "Edit Account"),
            canSave: editing != nil || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSave: {
                if accounts.save(id: editing?.id, label: name, token: token) { showingEditor = false }
            }, onCancel: { showingEditor = false }
        ) {
            Section {
                TextField("Account name", text: $name)
                    .accessibilityIdentifier("exaroton.nameField")
                SecureField(editing == nil ? "TOKEN" : "Leave empty to keep the current key", text: $token)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("exaroton.tokenField")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                Text("Stored in the macOS/iOS keychain and only used for exaroton requests.")
            }
            if let error = accounts.errorMessage { Text(verbatim: error).foregroundStyle(OrzMCTheme.Palette.danger) }
        }
        .presentationDetents([.large])
    }

    private func beginAdding() {
        editing = nil
        name = ""
        token = ""
        showingEditor = true
    }
}
