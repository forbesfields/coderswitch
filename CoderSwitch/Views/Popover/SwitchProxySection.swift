import SwiftUI
import CoderSwitchCore

/// Connects `SwitchProxyPanel` to the proxy, Claude Code launcher, and OAuth store.
struct SwitchProxySection: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(ProxySettings.self) private var settings
    @Environment(ProxyManager.self) private var proxy

    @State private var busyTargetID: UUID?
    @State private var message: SwitchMessage?

    private var claudeAccounts: [Account] {
        accountStore.accounts.filter { $0.isEnabled && $0.provider.isClaudeCodeCompatible }
    }

    var body: some View {
        SwitchProxyPanel(
            proxyStatus: proxy.status,
            baseURL: settings.baseURL,
            claudeTargets: claudeAccounts.map {
                SwitchTarget(id: $0.id, title: $0.label, subtitle: $0.provider.displayName)
            },
            oauthGroups: oauthGroups,
            busyTargetID: busyTargetID,
            message: message,
            onStartProxy: { proxy.start() },
            onStopProxy: { proxy.stop() },
            onCopyURL: copyURL,
            onOpenClaude: openClaudeCode,
            onRestoreOfficialClaude: restoreOfficialClaude,
            onSwitchOAuth: switchOAuth
        )
    }

    private var oauthGroups: [SwitchGroup] {
        OAuthProvider.allCases.compactMap { provider in
            let accounts = oauthStore.accounts(for: provider)
            guard !accounts.isEmpty else { return nil }
            return SwitchGroup(
                id: provider.id,
                title: provider.displayName,
                symbolName: provider.iconName,
                targets: accounts.map { SwitchTarget(id: $0.id, title: displayLabel(for: $0, provider: provider)) }
            )
        }
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settings.baseURL, forType: .string)
    }

    private func openClaudeCode(accountID: UUID) {
        guard let account = claudeAccounts.first(where: { $0.id == accountID }) else { return }
        message = nil
        do {
            try ClaudeCodeLauncher.open(
                account: account,
                apiKey: accountStore.apiKey(for: account),
                proxySettings: settings,
                proxyManager: proxy
            )
            message = SwitchMessage(text: "Claude Code opened with \(account.label).", isError: false)
        } catch ClaudeCodeLaunchError.cancelled {
            return
        } catch {
            message = SwitchMessage(text: "Claude Code launch failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func restoreOfficialClaude() {
        do {
            try ClaudeCodeConfigSwitcher().restoreOfficialClaude()
            message = SwitchMessage(text: "Claude Code restored to official auth.", isError: false)
        } catch {
            message = SwitchMessage(text: "Claude Code restore failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func switchOAuth(accountID: UUID) {
        guard let account = OAuthProvider.allCases.lazy
            .flatMap({ oauthStore.accounts(for: $0) })
            .first(where: { $0.id == accountID }) else { return }
        busyTargetID = accountID
        message = nil
        Task {
            do {
                try await oauthStore.switchToAccount(account)
                message = SwitchMessage(text: "Switched \(account.provider.displayName) to \(account.label).", isError: false)
            } catch {
                message = SwitchMessage(text: "Switch failed: \(error.localizedDescription)", isError: true)
            }
            busyTargetID = nil
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
