import SwiftUI
import CoderSwitchCore

/// Usage half of the popover: one card per enabled account, ordered by provider.
struct UsageSection: View {
    let accounts: [Account]
    let hasAnyAccounts: Bool
    let isPolling: Bool
    let onSignIn: (Account) -> Void
    let onOpenSettings: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Usage", systemImage: "chart.bar.fill")
            if accounts.isEmpty {
                emptyState
            } else {
                ForEach(accounts) { account in
                    AccountUsageCard(
                        account: account,
                        isChecking: isPolling && account.lastCheckedAt == nil,
                        onSignIn: { onSignIn(account) },
                        onOpenSettings: onOpenSettings
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: hasAnyAccounts ? "power.circle" : "person.crop.circle.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(hasAnyAccounts ? "All accounts are turned off" : "No accounts yet")
                .font(.subheadline.weight(.semibold))
            Text(hasAnyAccounts
                 ? "Turn one on in Settings to see its usage here."
                 : "Add a Claude, Codex, or API key account to watch its usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if hasAnyAccounts {
                Button("Open Settings", action: onOpenSettings)
            } else {
                Button("Add account…", action: onAddAccount)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .cardStyle()
    }
}
