import SwiftUI

struct StatusPopover: View {
    @Environment(AccountStore.self) private var store
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(ProxySettings.self) private var settings
    @Environment(ProxyManager.self) private var proxy
    @Environment(QuotaPoller.self) private var poller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CoderSwitch")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await poller.pollOnce() }
                } label: {
                    Image(systemName: poller.isPolling ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(poller.isPolling)
                .help("Refresh usage now")
            }

            ProxyStatusRow()

            Divider()

            OAuthQuickSwitch()

            Divider()

            if store.accounts.isEmpty {
                Text("No accounts yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(store.accountsByProvider, id: \.0) { provider, accounts in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(provider.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(accounts) { account in
                            AccountUsageRow(account: account)
                        }
                    }
                }
            }

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct OAuthQuickSwitch: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(ProxySettings.self) private var settings
    @State private var isExpanded = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Quick Switch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                let claudeAccounts = accountStore.accounts.filter(\.provider.isClaudeCodeCompatible)
                if !claudeAccounts.isEmpty {
                    Text("Claude Code")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(claudeAccounts) { account in
                        Button {
                            switchClaudeCode(to: account)
                        } label: {
                            HStack {
                                Image(systemName: "terminal")
                                    .font(.caption)
                                Text(account.label)
                                    .font(.caption)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!account.isEnabled || settings.adminKey.isEmpty)
                    }

                    Button {
                        restoreOfficialClaude()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                            Text("Official Claude")
                                .font(.caption)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(OAuthProvider.allCases) { provider in
                    let accounts = oauthStore.accounts(for: provider)
                    if !accounts.isEmpty {
                        Text(provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(accounts) { account in
                            Button {
                                Task { try? await oauthStore.switchToAccount(account) }
                            } label: {
                                HStack {
                                    Image(systemName: provider.iconName)
                                        .font(.caption)
                                    Text(displayLabel(for: account, provider: provider))
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func switchClaudeCode(to account: Account) {
        do {
            try ClaudeCodeConfigSwitcher().switchToCoderSwitch(
                account: account,
                proxyBaseURL: settings.baseURL,
                adminKey: settings.adminKey
            )
            statusMessage = "Claude Code switched to \(account.label)."
        } catch {
            statusMessage = "Claude Code switch failed: \(error.localizedDescription)"
        }
    }

    private func restoreOfficialClaude() {
        do {
            try ClaudeCodeConfigSwitcher().restoreOfficialClaude()
            statusMessage = "Claude Code restored to official auth."
        } catch {
            statusMessage = "Claude Code restore failed: \(error.localizedDescription)"
        }
    }

    private func displayLabel(for oauthAccount: OAuthAccount, provider: OAuthProvider) -> String {
        guard let accountProvider = Provider(rawValue: provider.rawValue) else {
            return oauthAccount.label
        }
        return accountStore.accounts.first { account in
            account.provider == accountProvider
                && (
                    account.id == oauthAccount.id
                    || (account.externalID != nil && account.externalID == oauthAccount.externalID)
                )
        }?.label ?? oauthAccount.label
    }
}

private struct AccountUsageRow: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(account.label)
                Spacer()
                if account.provider.isProxyRoutable {
                    Text("\(account.provider.routingSlug):\(account.label.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let error = account.lastCheckError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if account.usageLimits.isEmpty {
                if account.provider.quotaCheck == nil && account.provider.isProxyRoutable {
                    Text("No quota endpoint")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if account.lastCheckedAt == nil {
                    Text("Pending first check…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                let visibleLimits = account.menuBarUsageLimits
                if visibleLimits.isEmpty {
                    Text("No model limits shown in menu bar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Enable models in Settings > Accounts")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(visibleLimits) { limit in
                    UsageLimitBar(limit: limit)
                }
            }
            let today = account.tokenUsageTotal(period: .day)
            let allTime = account.tokenUsageTotal(period: .allTime)
            if !allTime.isEmpty {
                Text("Tokens today \(formatTokens(today.totalTokens)) • all \(formatTokens(allTime.totalTokens))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct UsageLimitBar: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let desc = limit.remainingDescription {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let used = limit.used {
                    Text(limit.displayValue(used))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = limit.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(limit.usageTintColor)
            }
        }
    }
}

extension UsageLimit {
    var usageTintColor: Color {
        guard let fraction else { return .secondary }
        switch fraction {
        case ...0.4: return .green
        case ...0.6: return .yellow
        case ...0.8: return .orange
        default: return .red
        }
    }
}

private struct ProxyStatusRow: View {
    @Environment(ProxySettings.self) private var settings
    @Environment(ProxyManager.self) private var proxy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
                Spacer()
                if proxy.status.isRunning {
                    Button("Stop") { proxy.stop() }
                        .buttonStyle(.borderless)
                } else {
                    Button("Start") { proxy.start() }
                        .buttonStyle(.borderless)
                }
            }
            if proxy.status.isRunning {
                HStack(spacing: 6) {
                    Text(settings.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        copyToPasteboard(settings.baseURL)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy proxy URL")
                }
            }
        }
    }

    private var statusColor: Color {
        switch proxy.status {
        case .running: .green
        case .starting, .stopping: .yellow
        case .stopped: .secondary
        case .failed: .red
        }
    }

    private var statusText: String {
        switch proxy.status {
        case .stopped: "Proxy stopped"
        case .starting: "Starting…"
        case .running(let port): "Proxy running on :\(port)"
        case .stopping: "Stopping…"
        case .failed(let m): "Failed: \(m)"
        }
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

private func formatTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        String(format: "%.1fK", Double(value) / 1_000)
    default:
        "\(value)"
    }
}
