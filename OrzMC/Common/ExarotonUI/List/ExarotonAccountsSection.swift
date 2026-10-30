import OrzMCDesignSystem
import SwiftUI

struct ExarotonAccountsSection: View {
    @Environment(ExarotonAccountsModel.self) private var accounts
    @State private var editing: ExarotonAccount?
    @State private var showingEditor = false
    @State private var name = ""
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            RemoteProviderHeader(name: "exaroton", systemImage: "cloud",
                                 count: accounts.models.values.reduce(0) { $0 + $1.servers.count },
                                 identifier: "exaroton.section", addIdentifier: "exaroton.addAccount") {
                editing = nil; name = ""; token = ""; showingEditor = true
            }
            if accounts.accounts.isEmpty {
                Text("Add an account to see its instances.", comment: "Remote provider empty state")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(accounts.accounts) { account in
                if let model = accounts.models[account.id] {
                    VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                        RemoteAccountHeader(name: account.displayName, isLoading: model.isLoadingList) {
                            Menu {
                                Button("Refresh") { Task { await model.reloadList() } }
                                Button("Edit Account", systemImage: "slider.horizontal.3") {
                                    editing = account; name = account.label; token = ""; showingEditor = true
                                }
                                Button("Remove Account", systemImage: "trash", role: .destructive) { accounts.remove(account.id) }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                            .accessibilityLabel(Text("Account actions", comment: "Account menu accessibility label"))
                        }
                        ExarotonServerList().environment(model)
                            .id(ObjectIdentifier(model))
                    }
                    .padding(OrzMCTheme.Spacing.md).orzMCPanel()
                    .task(id: ObjectIdentifier(model)) { await accounts.resolveDefaultName(for: account.id) }
                }
            }
            if let error = accounts.errorMessage {
                Text(verbatim: error).font(.caption).foregroundStyle(OrzMCTheme.Palette.danger)
            }
        }
        .sheet(isPresented: $showingEditor) {
            RemoteAccountEditor(
                title: editing == nil ? String(localized: "Add Account") : String(localized: "Edit Account"),
                canSave: editing != nil || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSave: {
                    if accounts.save(id: editing?.id, label: name, token: token) { showingEditor = false }
                }, onCancel: { showingEditor = false }
            ) {
                Section {
                    TextField("Account name", text: $name)
                    SecureField(editing == nil ? "TOKEN" : "Leave empty to keep the current key", text: $token)
                        .autocorrectionDisabled()
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
    }
}
