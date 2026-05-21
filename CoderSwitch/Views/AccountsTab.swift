import SwiftUI
import AppKit

struct AccountsTab: View {
    @Environment(AccountStore.self) private var store
    @State private var showingAdd = false
    @State private var search = ""
    @State private var sort: SortOption = .label
    @State private var providerFilter: Provider?

    enum SortOption: String, CaseIterable, Identifiable {
        case label, provider, recent
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .label: "Name"
            case .provider: "Provider"
            case .recent: "Recently checked"
            }
        }
    }

    private var filteredAccounts: [Account] {
        var items = store.accounts
        if let providerFilter {
            items = items.filter { $0.provider == providerFilter }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.label.lowercased().contains(query)
                    || $0.provider.displayName.lowercased().contains(query)
                    || ($0.defaultModel ?? "").lowercased().contains(query)
            }
        }
        switch sort {
        case .label:
            items.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .provider:
            items.sort {
                if $0.provider.displayName == $1.provider.displayName {
                    return $0.label < $1.label
                }
                return $0.provider.displayName < $1.provider.displayName
            }
        case .recent:
            items.sort { ($0.lastCheckedAt ?? .distantPast) > ($1.lastCheckedAt ?? .distantPast) }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AccountsToolbar(
                    search: $search,
                    sort: $sort,
                    providerFilter: $providerFilter,
                    availableProviders: Array(Set(store.accounts.map(\.provider))).sorted { $0.displayName < $1.displayName }
                )
                Divider()
                List {
                    if store.accounts.isEmpty {
                        ContentUnavailableView(
                            "No accounts",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("Click + to add an API key.")
                        )
                    } else if filteredAccounts.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ForEach(filteredAccounts) { account in
                            AccountRow(account: account)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddAccountView()
                }
            }
        }
    }
}

private struct AccountsToolbar: View {
    @Binding var search: String
    @Binding var sort: AccountsTab.SortOption
    @Binding var providerFilter: Provider?
    let availableProviders: [Provider]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search accounts", text: $search)
                .textFieldStyle(.roundedBorder)
            Menu {
                Button("All providers") { providerFilter = nil }
                Divider()
                ForEach(availableProviders, id: \.self) { provider in
                    Button(provider.displayName) { providerFilter = provider }
                }
            } label: {
                Label(providerFilter?.displayName ?? "All providers", systemImage: "line.3.horizontal.decrease.circle")
            }
            Menu {
                ForEach(AccountsTab.SortOption.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                Label("Sort: \(sort.displayName)", systemImage: "arrow.up.arrow.down")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct AccountRow: View {
    @Environment(AccountStore.self) private var store
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(ProxySettings.self) private var proxySettings
    @Environment(ProxyManager.self) private var proxyManager
    let account: Account
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
    @State private var fetchError: String?
    @State private var healthMessage: String?
    @State private var confirmingDelete = false
    @State private var showingBreaker = false
    @State private var showingRename = false
    @State private var nicknameDraft = ""
    @State private var claudeLaunchError: String?
    @State private var showingGoogleModels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(providerColor)
                    .font(.system(size: 8))
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.label)
                            .font(.body)
                        if let authSource = codexAuthSource {
                            Text(authSource.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .help("Codex account source")
                        }
                        Text(account.provider.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(providerColor.opacity(0.15), in: Capsule())
                        if !account.isEnabled {
                            Text("DISABLED")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        if account.shouldWarnAboutFailures() {
                            Label("Failures", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Failure threshold exceeded — check provider status")
                        }
                    }
                    Text(account.endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let defaultModel = account.defaultModel {
                        Text("Default: \(defaultModel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let lastChecked = account.lastCheckedAt {
                        Text("Checked \(lastChecked, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button {
                    store.setEnabled(accountID: account.id, isEnabled: !account.isEnabled)
                } label: {
                    Image(systemName: account.isEnabled ? "power.circle.fill" : "power.circle")
                }
                .buttonStyle(.borderless)
                .help(account.isEnabled ? "Disable routing and quota polling" : "Enable routing and quota polling")
                Button {
                    nicknameDraft = account.label
                    showingRename = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit nickname")
                Button {
                    showingBreaker = true
                } label: {
                    Image(systemName: account.circuitBreaker.enabled ? "shield.lefthalf.filled" : "shield")
                }
                .buttonStyle(.borderless)
                .help("Circuit breaker (warn-only)")
                if account.provider != .codex {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Image(systemName: isTestingConnection ? "waveform.path.ecg" : "network")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isTestingConnection)
                    .help("Test provider connection")
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        Image(systemName: isFetchingModels ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFetchingModels)
                    .help("Fetch models")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if !account.provider.isProxyRoutable {
                Text(account.provider == .codex
                     ? "OAuth export and quota tracking only; proxy routing uses API-key providers."
                     : "Quota tracking only; proxy routing uses API-key providers.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if account.usageLimits.isEmpty {
                    Text(account.lastCheckError ?? "Pending first quota check...")
                        .font(.caption2)
                        .foregroundStyle(account.lastCheckError == nil ? Color.secondary : Color.orange)
                } else if account.provider == .googleAntigravity {
                    GoogleModelLimitDisclosure(
                        account: account,
                        isExpanded: $showingGoogleModels
                    )
                } else {
                    ForEach(account.usageLimits) { limit in
                        AccountLimitBar(limit: limit)
                    }
                }
            } else if let models = account.availableModels, !models.isEmpty {
                Picker("Default model", selection: defaultModelSelection) {
                    ForEach(models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
            } else {
                Text("Fetch models to choose a default.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let fetchError {
                Text(fetchError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let healthMessage {
                Text(healthMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if account.provider.isClaudeCodeCompatible {
                Button {
                    openClaudeCode()
                } label: {
                    Label("Open Claude Code", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Choose a folder and launch Claude Code through this account")
            }

            if let claudeLaunchError {
                Text(claudeLaunchError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .opacity(account.isEnabled ? 1 : 0.58)
        .confirmationDialog(
            "Delete \(account.label)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { store.delete(account) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingBreaker) {
            CircuitBreakerSheet(account: account)
        }
        .sheet(isPresented: $showingRename) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Nickname")
                    .font(.headline)
                TextField("Nickname", text: $nicknameDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showingRename = false }
                    Button("Save") {
                        store.rename(accountID: account.id, label: nicknameDraft)
                        showingRename = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 360)
        }
    }

    private var providerColor: Color {
        switch account.provider {
        case .codex: return .blue
        case .openRouter: return .purple
        case .miniMax: return .pink
        case .anthropic, .anthropicCompatible: return .orange
        case .openAI, .openAICompatible: return .green
        case .googleAntigravity: return .indigo
        }
    }

    private var codexAuthSource: OAuthAccountAuthSource? {
        guard account.provider == .codex else { return nil }
        return oauthStore.codexAccount(matching: account)?.authSource
    }

    private var defaultModelSelection: Binding<String> {
        Binding(
            get: { account.defaultModel ?? account.availableModels?.first?.id ?? "" },
            set: { modelID in
                store.setDefaultModel(accountID: account.id, modelID: modelID)
            }
        )
    }

    private func fetchModels() async {
        isFetchingModels = true
        fetchError = nil
        healthMessage = nil
        let apiKey = store.apiKey(for: account)
        do {
            let models = try await ProviderModelFetcher().fetchModels(account: account, apiKey: apiKey)
            store.updateModels(accountID: account.id, models: models)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingModels = false
    }

    private func testConnection() async {
        isTestingConnection = true
        fetchError = nil
        healthMessage = nil
        let started = Date()
        let apiKey = store.apiKey(for: account)
        do {
            let models = try await ProviderModelFetcher().fetchModels(account: account, apiKey: apiKey)
            store.updateModels(accountID: account.id, models: models)
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            healthMessage = "Connection OK in \(latency) ms; \(models.count) models available."
        } catch {
            fetchError = "Connection failed: \(error.localizedDescription)"
        }
        isTestingConnection = false
    }

    private func openClaudeCode() {
        claudeLaunchError = nil
        do {
            try ClaudeCodeLauncher.open(
                account: account,
                proxySettings: proxySettings,
                proxyManager: proxyManager
            )
        } catch ClaudeCodeLaunchError.cancelled {
            return
        } catch {
            claudeLaunchError = error.localizedDescription
        }
    }
}

private enum ClaudeCodeLaunchError: LocalizedError {
    case incompatibleAccount
    case cancelled
    case terminalLaunchFailed

    var errorDescription: String? {
        switch self {
        case .incompatibleAccount:
            return "This account cannot be used with Claude Code."
        case .cancelled:
            return nil
        case .terminalLaunchFailed:
            return "Could not open Claude Code in Terminal."
        }
    }
}

private enum ClaudeCodeLauncher {
    @MainActor
    static func open(
        account: Account,
        proxySettings: ProxySettings,
        proxyManager: ProxyManager
    ) throws {
        guard account.provider.isClaudeCodeCompatible else {
            throw ClaudeCodeLaunchError.incompatibleAccount
        }
        guard let folder = chooseFolder() else {
            throw ClaudeCodeLaunchError.cancelled
        }

        switch proxyManager.status {
        case .running, .starting:
            break
        default:
            proxyManager.start()
        }

        try ClaudeCodeConfigSwitcher().switchToCoderSwitch(
            account: account,
            proxyBaseURL: proxySettings.baseURL,
            adminKey: proxySettings.adminKey
        )

        let scopedToken = "\(proxySettings.adminKey):\(account.id.uuidString)"
        let script = try createLaunchScript(
            folder: folder,
            baseURL: proxySettings.baseURL,
            authToken: scopedToken,
            defaultModel: account.claudeCodeDefaultModel
        )

        do {
            try runInTerminal(script)
        } catch {
            try? FileManager.default.removeItem(at: script)
            throw error
        }
    }

    @MainActor
    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Claude Code"
        panel.message = "Choose a folder for Claude Code."
        panel.prompt = "Open Claude Code"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func createLaunchScript(
        folder: URL,
        baseURL: String,
        authToken: String,
        defaultModel: String?
    ) throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("coderswitch-claude-\(UUID().uuidString).zsh")
        let modelEnvironment = defaultModel.map { model in
            """
            export ANTHROPIC_MODEL=\(model.shellQuotedForTerminal)
            export ANTHROPIC_DEFAULT_HAIKU_MODEL=\(model.shellQuotedForTerminal)
            export ANTHROPIC_DEFAULT_SONNET_MODEL=\(model.shellQuotedForTerminal)
            export ANTHROPIC_DEFAULT_OPUS_MODEL=\(model.shellQuotedForTerminal)
            """
        } ?? """
        unset ANTHROPIC_MODEL
        unset ANTHROPIC_DEFAULT_HAIKU_MODEL
        unset ANTHROPIC_DEFAULT_SONNET_MODEL
        unset ANTHROPIC_DEFAULT_OPUS_MODEL
        """
        let contents = """
        #!/bin/zsh
        unset HISTFILE
        rm -f \(script.path.shellQuotedForTerminal)
        cd \(folder.path.shellQuotedForTerminal) || exit 1
        unset ANTHROPIC_API_KEY
        unset ANTHROPIC_MODEL
        unset ANTHROPIC_DEFAULT_HAIKU_MODEL
        unset ANTHROPIC_DEFAULT_SONNET_MODEL
        unset ANTHROPIC_DEFAULT_OPUS_MODEL
        export ANTHROPIC_BASE_URL=\(baseURL.shellQuotedForTerminal)
        export ANTHROPIC_AUTH_TOKEN=\(authToken.shellQuotedForTerminal)
        \(modelEnvironment)
        exec claude --dangerously-skip-permissions
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    private static func runInTerminal(_ script: URL) throws {
        let appleScript = """
        tell application "Terminal"
            activate
            do script \(script.path.shellQuotedForTerminal.appleScriptLiteral)
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ClaudeCodeLaunchError.terminalLaunchFailed
        }
    }
}

private extension String {
    var shellQuotedForTerminal: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptLiteral: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

private struct GoogleModelLimitDisclosure: View {
    @Environment(AccountStore.self) private var store
    let account: Account
    @Binding var isExpanded: Bool

    private var defaultVisibleIDs: Set<String> {
        Set(account.usageLimits
            .filter { !$0.isGoogleAntigravityInternalModel }
            .prefix(3)
            .map(\.id))
    }

    private var userFacingLimits: [UsageLimit] {
        account.usageLimits.filter { !$0.isGoogleAntigravityInternalModel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text("Model limits")
                        .font(.caption2.weight(.semibold))
                    Text("choose what appears in the menu bar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(account.menuBarUsageLimits.count) shown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide model visibility controls" : "Show model visibility controls")

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Show defaults") {
                            store.setMenuBarUsageLimitIDs(accountID: account.id, limitIDs: defaultVisibleIDs)
                        }
                        Button("Show all") {
                            store.setMenuBarUsageLimitIDs(
                                accountID: account.id,
                                limitIDs: Set(userFacingLimits.map(\.id))
                            )
                        }
                        Button("Hide all") {
                            store.setMenuBarUsageLimitIDs(accountID: account.id, limitIDs: [])
                        }
                        Spacer()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)

                    if userFacingLimits.isEmpty {
                        Text("No user-facing Google model limits returned yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(userFacingLimits) { limit in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Toggle("Show in menu bar", isOn: menuBarBinding(for: limit))
                                    .toggleStyle(.checkbox)
                                    .font(.caption2)
                                    .frame(width: 132, alignment: .leading)
                                    .help("Show this model in the menu bar")
                                AccountLimitBar(limit: limit)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func menuBarBinding(for limit: UsageLimit) -> Binding<Bool> {
        Binding(
            get: { account.menuBarUsageLimits.contains { $0.id == limit.id } },
            set: { isVisible in
                store.setMenuBarUsageLimitVisible(
                    accountID: account.id,
                    limitID: limit.id,
                    isVisible: isVisible
                )
            }
        )
    }
}

private struct AccountLimitBar: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(limit.remainingDescription ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let fraction = limit.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(limit.usageTintColor)
            }
            if let resetAt = limit.resetAt {
                Text("Resets \(resetAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
