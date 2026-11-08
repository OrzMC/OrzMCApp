//
//  StorageModePicker.swift
//  OrzMC
//
//  「保存方式」三档选择（仅本次安装 / 保留在本机 / iCloud 同步）。
//  设计口径见 `docs/server-storage-design-2026-11-04.md`。
//
//  三条约定（界面侧）：
//   1. 不可用的档位（例如没开 Keychain Sharing 时的 iCloud）**置灰 + 说明原因**，不给"选了才报错"；
//   2. 切换只在**保存时**真正执行（`ServerSecretsStore.move`），取消不会动数据；
//   3. 迁移失败时保留原资料，并把错误显示在表单里。
//

import OrzMCDesignSystem
import OrzMCFoundation
import SwiftUI

struct StorageModePicker: View {
    @Binding var mode: ServerRecordStorageMode
    /// 自动化锚点前缀（例如 `selfHosted` → `selfHosted.storageMode.installation`）。
    var identifierPrefix: String

    var body: some View {
        Picker(String(localized: "Storage"), selection: $mode) {
            ForEach(ServerRecordStorageMode.allCases, id: \.self) { option in
                row(for: option)
                    .tag(option)
                    .disabled(!isAvailable(option))
                    .accessibilityIdentifier("\(identifierPrefix).storageMode.\(option.rawValue)")
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func isAvailable(_ option: ServerRecordStorageMode) -> Bool {
        ServerSecretsStore.isAvailable(option)
    }

    private func row(for option: ServerRecordStorageMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(option))
            Text(caption(option))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func title(_ option: ServerRecordStorageMode) -> LocalizedStringKey {
        switch option {
        case .installation: return "This install only"
        case .device: return "Keep on this device"
        case .iCloud: return "Sync with iCloud"
        }
    }

    /// 每档一句话说明"它到底怎么活"——用户选的是**生命周期**，不是存储位置。
    private func caption(_ option: ServerRecordStorageMode) -> LocalizedStringKey {
        switch option {
        case .installation:
            return "Survives app restarts. Lost if you reinstall the app or move to another device."
        case .device:
            return "Recoverable after reinstalling. Never leaves this device."
        case .iCloud:
            return ServerSecretsStore.isAvailable(.iCloud)
                ? "Follows your Apple Account, so other devices can use it too."
                : "Unavailable: this build has no Keychain sharing group (or iCloud Keychain is off)."
        }
    }
}

/// 把「保存方式」的切换落到凭据存储上；表单在保存时调用。
enum StorageModeMigration {
    enum Failure: LocalizedError {
        case move(any Error)

        var errorDescription: String? {
            switch self {
            case .move(let error):
                return (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Could not move the saved credentials.")
            }
        }
    }

    /// 把凭据从 `from` 搬到 `to`。同档位时什么都不做。
    static func apply(
        id: UUID,
        provider: ServerSecretsStore.Provider,
        from: ServerRecordStorageMode,
        to: ServerRecordStorageMode
    ) throws {
        guard from != to else { return }
        do {
            try ServerSecretsStore.move(id: id, provider: provider, from: from, to: to)
        } catch {
            throw Failure.move(error)
        }
    }
}
