import SwiftUI
import UniformTypeIdentifiers

struct OAuthAccountsTab: View {
    @Environment(OAuthStore.self) private var store
    @Environment(AccountStore.self) private var accountStore
    @State private var showingAdd = false
    @State private var showingCodexAuthImporter = false
    @State private var selectedProvider: OAuthProvider?
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var importMessage: String?
    @State private var importFailed = false

    var body: some View {
        NavigationStack {
            List {
                if let importMessage {
                    Section {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(importFailed ? .red : .secondary)
                    }
                }

                if store.accounts.isEmpty {
                    ContentUnavailableView(
                        "No OAuth accounts",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Connect your Codex or Gemini account to get started.")
                    )
                } else {
                    ForEach(OAuthProvider.allCases) { provider in
                        let accounts = store.accounts(for: provider)
                        if !accounts.isEmpty {
                            Section(provider.displayName) {
                                ForEach(accounts) { account in
                                    OAuthAccountRow(account: account, onSwitch: {
                                        try await store.switchToAccount(account)
                                    }, onDelete: {
                                        deleteOAuthAccount(account)
                                    })
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        deleteOAuthAccount(accounts[index])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("OAuth Accounts")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button {
                            showingCodexAuthImporter = true
                        } label: {
                            Label("Import Codex auth.json", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        ForEach(OAuthProvider.allCases) { provider in
                            Button {
                                selectedProvider = provider
                                showingAdd = true
                            } label: {
                                Label("Add \(provider.displayName)", systemImage: provider.iconName)
                            }
                        }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingCodexAuthImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: true
            ) { result in
                importCodexAuth(result)
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                if isAuthenticating {
                    store.cancelOAuthFlow()
                }
                isAuthenticating = false
                authError = nil
                selectedProvider = nil
            }) {
                if let provider = selectedProvider {
                    OAuthFlowView(provider: provider, isAuthenticating: $isAuthenticating, authError: $authError) {
                        showingAdd = false
                        accountStore.syncCodexAccounts(from: store.accounts(for: .codex))
                        accountStore.syncGoogleAntigravityAccounts(from: store.accounts(for: .gemini))
                    }
                }
            }
        }
    }

    private func importCodexAuth(_ result: Result<[URL], Error>) {
        importMessage = nil
        importFailed = false
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            var importedCount = 0
            var updatedCount = 0

            for url in urls {
                let securityScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if securityScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let imported = try store.importCodexAuth(from: url)
                if imported.didUpdate {
                    updatedCount += 1
                } else {
                    importedCount += 1
                }
            }

            accountStore.syncCodexAccounts(from: store.accounts(for: .codex))
            accountStore.syncGoogleAntigravityAccounts(from: store.accounts(for: .gemini))
            importMessage = "Imported \(importedCount) Codex account\(importedCount == 1 ? "" : "s"); updated \(updatedCount)."
        } catch {
            importFailed = true
            importMessage = "Could not import Codex auth.json: \(error.localizedDescription)"
        }
    }

    private func deleteOAuthAccount(_ account: OAuthAccount) {
        store.delete(account)
        if let linkedAccount = accountStore.accounts.first(where: { providerAccount in
            isLinked(providerAccount, to: account)
        }) {
            accountStore.delete(linkedAccount)
        }
    }

    private func isLinked(_ providerAccount: Account, to oauthAccount: OAuthAccount) -> Bool {
        let expectedProvider: Provider = oauthAccount.provider == .codex ? .codex : .googleAntigravity
        guard providerAccount.provider == expectedProvider else { return false }
        return providerAccount.id == oauthAccount.id
            || (oauthAccount.externalID != nil && providerAccount.externalID == oauthAccount.externalID)
            || (oauthAccount.email != nil && providerAccount.label == oauthAccount.email)
            || providerAccount.label == oauthAccount.label
    }
}

struct OAuthAccountRow: View {
    let account: OAuthAccount
    let onSwitch: () async throws -> Void
    let onDelete: () -> Void
    @State private var isSwitching = false
    @State private var confirmingDelete = false
    @State private var switchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.body)
                    if let email = account.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if account.token.isExpired {
                        Text("Token expired")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if account.token.isNearExpiry {
                        Text("Token expiring soon")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if let switchError {
                        Text(switchError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        isSwitching = true
                        switchError = nil
                        Task {
                            do {
                                try await onSwitch()
                            } catch {
                                switchError = error.localizedDescription
                            }
                            isSwitching = false
                        }
                    } label: {
                        if isSwitching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Install")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSwitching)
                    .help("Write this account to CLIProxyAPI's auth directory")

                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete OAuth account")
                }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete \(account.label)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
