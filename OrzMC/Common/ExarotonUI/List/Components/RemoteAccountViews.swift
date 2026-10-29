import OrzMCDesignSystem
import SwiftUI

/// Shared account header; provider-specific menus and contents stay with their provider.
struct RemoteAccountHeader<Actions: View>: View {
    let name: String
    let subtitle: String
    let isLoading: Bool
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                Text(verbatim: name).font(.headline)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: OrzMCTheme.Spacing.xs)
            if isLoading { ProgressView().controlSize(.small) }
            actions()
        }
    }
}

struct RemoteAccountEditor<Fields: View>: View {
    let title: String
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        NavigationStack {
            Form { fields() }
                .formStyle(.grouped)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: onSave).disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }
}

/// Both providers use the same name/status layout; long names and large text can wrap the badge.
struct RemoteInstanceHeading: View {
    let name: String
    let statusTitle: String?
    let statusStyle: OrzMCStatusStyle

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                Text(verbatim: name).font(.headline).fixedSize(horizontal: true, vertical: false)
                badge
            }
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                Text(verbatim: name).font(.headline).fixedSize(horizontal: false, vertical: true)
                badge
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let statusTitle { OrzMCStatusBadge(verbatim: statusTitle, style: statusStyle) }
    }
}

struct RemoteProviderHeader: View {
    let name: String
    let systemImage: String
    let count: Int
    let identifier: String

    var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.xs) {
            Label {
                Text(verbatim: name).accessibilityIdentifier(identifier)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .font(.headline)
            if count > 0 {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
