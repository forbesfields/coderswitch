import SwiftUI
import CoderSwitchCore

/// Add-account wizard: pick a provider, pick a credential source (skipped when there is only one),
/// then fill the matching form. Shown in a window from the popover and as a sheet from Settings.
struct AddAccountFlow: View {
    let onFinish: () -> Void

    @Environment(AccountStore.self) private var accountStore
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(QuotaPoller.self) private var poller

    private enum Step: Hashable {
        case source(Provider)
        case form(Provider, AccountCredentialSource)
    }

    @State private var path: [Step] = []
    @State private var isAuthenticating = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 480, height: 620)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 8) {
            if !path.isEmpty {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch path.last {
        case nil: "Add account"
        case .source(let provider): provider.displayName
        case .form(let provider, _): provider.displayName
        }
    }

    private var subtitle: String? {
        switch path.last {
        case nil: "Pick a provider"
        case .source: "How should CoderSwitch read usage?"
        case .form(_, let source): source.displayName
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch path.last {
        case nil:
            ProviderPickerList(onPick: pick)
        case .source(let provider):
            SourcePickerList(provider: provider) { source in
                path.append(.form(provider, source))
            }
        case .form(let provider, let source):
            form(provider: provider, source: source)
        }
    }

    @ViewBuilder
    private func form(provider: Provider, source: AccountCredentialSource) -> some View {
        switch source {
        case .apiKey:
            APIKeyAccountForm(provider: provider, submit: add)
        case .oauth:
            if let oauthProvider = OAuthProvider(provider) {
                OAuthFlowView(
                    provider: oauthProvider,
                    isAuthenticating: $isAuthenticating,
                    authError: $authError,
                    onComplete: { oauthFinished() },
                    onCancel: goBack
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .webSession where provider == .customWeb:
            CustomWebAccountForm(submit: add)
        case .webSession, .claudeCodeKeychain, .localCLI:
            SourceAccountForm(provider: provider, source: source, submit: add)
        }
    }

    // MARK: Actions

    private func pick(_ provider: Provider) {
        let sources = provider.supportedCredentialSources
        if let only = sources.first, sources.count == 1 {
            path = [.form(provider, only)]
        } else {
            path = [.source(provider)]
        }
    }

    private func goBack() {
        if isAuthenticating {
            oauthStore.cancelOAuthFlow()
            isAuthenticating = false
        }
        authError = nil
        // A skipped source step means the form's parent is the provider list.
        if case .form(let provider, _) = path.last, provider.supportedCredentialSources.count > 1 {
            path = [.source(provider)]
        } else {
            path = []
        }
    }

    private func cancel() {
        if isAuthenticating {
            oauthStore.cancelOAuthFlow()
            isAuthenticating = false
        }
        onFinish()
    }

    private func add(_ account: Account, apiKey: String?) throws {
        try accountStore.add(account, apiKey: apiKey)
        if account.usesWebSession {
            AppShell.shared.showLoginWindow(for: account)
        }
        finish()
    }

    private func oauthFinished() {
        accountStore.syncCodexAccounts(from: oauthStore.accounts(for: .codex))
        accountStore.syncGoogleAntigravityAccounts(from: oauthStore.accounts(for: .gemini))
        finish()
    }

    private func finish() {
        Task { await poller.pollOnce() }
        onFinish()
    }
}

private extension OAuthProvider {
    init?(_ provider: Provider) {
        switch provider {
        case .codex: self = .codex
        case .googleAntigravity: self = .gemini
        default: return nil
        }
    }
}
