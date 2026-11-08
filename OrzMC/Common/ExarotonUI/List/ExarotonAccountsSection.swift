import OrzMCDesignSystem
import OrzMCFoundation
import OrzMCRemoteHosting
import SwiftUI

/// **exaroton** 分组：图标标题 + 每个账号一张卡（实例 + 额度池）。
///
/// 结构走 `RemoteProviderSection` / `RemoteAccountCard` / `RemoteAccountMenu`（与 MCSM 同一套骨架），
/// 这里只保留 exaroton 特有的部分：实例卡、额度池；账号表单由 `ExarotonContent` 统一弹
/// （只有在那一层，「一家都没配」的空态页也能弹出表单）。
struct ExarotonAccountsSection: View {
    /// 打开某个账号的编辑表单（由页面层弹 sheet）。
    let onEditAccount: (ExarotonAccount) -> Void
    @Environment(ExarotonAccountsModel.self) private var accounts

    private var instanceCount: Int {
        accounts.models.values.reduce(0) { $0 + $1.servers.count }
    }

    var body: some View {
        RemoteProviderSection(
            name: "Exaroton",
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
    }

    // MARK: - 组件

    private func accountCard(_ account: ExarotonAccount, model: ExarotonServerModel) -> some View {
        RemoteAccountCard(name: account.displayName, isLoading: model.isLoadingList) {
            RemoteAccountMenu(
                onRefresh: { Task { await model.reloadList() } },
                onEdit: { onEditAccount(account) },
                onRemove: { accounts.remove(account.id) }
            )
        } content: {
            ExarotonServerList()
                .environment(model)
                .id(ObjectIdentifier(model))
        }
        .task(id: ObjectIdentifier(model)) { await accounts.resolveDefaultName(for: account.id) }
    }
}

/// exaroton 账号表单（新增 / 编辑）：账号名 + TOKEN。
///
/// 从分组里搬出来单独成视图，是因为**空态页也要能弹**（一个账号都没有时分组还没渲染）。
struct ExarotonAccountEditorSheet: View {
    /// `nil` = 新增。
    let existing: ExarotonAccount?
    /// 关掉 sheet（由页面层把 `editorSheet` 置空；**不能只 `dismiss()`**：
    /// `sheet(item:)` 的 item 不置空时，下一次presentation 会被忽略）。
    let onClose: () -> Void
    @Environment(ExarotonAccountsModel.self) private var accounts

    @State private var name: String
    @State private var token = ""
    @State private var storageMode: ServerRecordStorageMode

    init(existing: ExarotonAccount?, onClose: @escaping () -> Void) {
        self.existing = existing
        self.onClose = onClose
        _name = State(initialValue: existing?.label ?? "")
        _storageMode = State(initialValue: existing?.storageMode ?? .device)
    }

    var body: some View {
        RemoteAccountEditor(
            title: existing == nil ? String(localized: "Add Account") : String(localized: "Edit Account"),
            canSave: existing != nil || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSave: {
                if accounts.save(
                    id: existing?.id, label: name, token: token, storageMode: storageMode
                ) { onClose() }
            },
            onCancel: onClose
        ) {
            Section {
                TextField("Account name", text: $name)
                    .accessibilityIdentifier("exaroton.nameField")
                SecureField(
                    existing == nil ? "TOKEN" : "Leave empty to keep the current key",
                    text: $token
                )
                .autocorrectionDisabled()
                .accessibilityIdentifier("exaroton.tokenField")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            } footer: {
                Text("Stored in the macOS/iOS keychain and only used for Exaroton requests.")
            }
            Section {
                StorageModePicker(mode: $storageMode, identifierPrefix: "exaroton")
            } header: {
                Text("Storage")
            } footer: {
                Text("Where the TOKEN is kept. Changing it moves the saved token.")
            }
            if let error = accounts.errorMessage {
                Text(verbatim: error).foregroundStyle(OrzMCTheme.Palette.danger)
            }
        }
        .presentationDetents([.large])
    }
}
