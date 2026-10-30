import SwiftUI
import CoderSwitchCore
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
                            description: Text("Click + to add an account.")
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
                AddAccountFlow(onFinish: { showingAdd = false })
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
    @State private var showingEdit = false
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
                    if !account.endpoint.isEmpty {
                        Text(account.endpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if account.effectiveCredentialSource != .oauth {
                        Label(account.effectiveCredentialSource.displayName, systemImage: account.effectiveCredentialSource.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let defaultModel = account.defaultModel {
                        Text("Default: \(defaultModel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let accessSummary {
                        Text(accessSummary)
                            .font(.caption2)
                            .foregroundStyle(accessSummaryColor)
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
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit account")
                Button {
                    showingBreaker = true
                } label: {
                    Image(systemName: account.circuitBreaker.enabled ? "shield.lefthalf.filled" : "shield")
                }
                .buttonStyle(.borderless)
                .help("Circuit breaker (warn-only)")
                if account.provider.isProxyRoutable {
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

            if account.provider.isProxyRoutable && account.provider.supportsUsagePolling {
                if let error = account.lastCheckError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if account.usageLimits.isEmpty {
                    Text("Pending first quota check...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.usageLimits) { limit in
                        AccountLimitBar(limit: limit)
                    }
                }
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

            if account.usesWebSession {
                Button {
                    AppShell.shared.showLoginWindow(for: account)
                } label: {
                    Label("Sign in again", systemImage: "person.badge.key")
                }
                .buttonStyle(.bordered)
                .help("Open this account's sign-in window")
            }

            if account.provider.isClaudeCodeCompatible {
                Button {
                    openClaudeCode()
                } label: {
                    Label("Open Claude Code", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Choose a folder and launch Claude Code with this account's endpoint and API key")
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
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingBreaker) {
            CircuitBreakerSheet(account: account)
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                EditAccountView(account: account)
            }
        }
    }

    private var providerColor: Color { account.provider.tintColor }

    /// Codex and Antigravity cards are rebuilt from their stored sign-in at launch, so deleting
    /// the card also deletes that sign-in (and, for Codex, stops the ~/.codex re-import).
    private func deleteAccount() {
        let linkedSignIn = switch account.provider {
        case .codex: oauthStore.codexAccount(matching: account)
        case .googleAntigravity: oauthStore.geminiAccount(matching: account)
        default: nil as OAuthAccount?
        }
        if let linkedSignIn {
            oauthStore.delete(linkedSignIn)
        }
        store.delete(account)
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

    private var accessSummary: String? {
        let start = account.accessGainedAt
        let duration = account.accessDuration
        guard start != nil || duration != nil else { return nil }

        var parts: [String] = []
        if let start {
            parts.append("Access: \(start.formatted(date: .abbreviated, time: .omitted))")
        }
        if let duration {
            parts.append("Period: \(duration.value) \(duration.unit.displayName(for: duration.value))")
        }
        if let expiry = account.accessExpiresAt() {
            parts.append("Expires: \(expiry.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " | ")
    }

    private var accessSummaryColor: Color {
        guard let expiry = account.accessExpiresAt() else { return .secondary }
        return expiry < Date() ? .orange : .secondary
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
                apiKey: store.apiKey(for: account),
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

private struct EditAccountView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var provider: Provider
    @State private var label: String
    @State private var apiKey: String = ""
    @State private var customEndpoint: String
    @State private var defaultModel: String
    @State private var claudeOpusModel: String
    @State private var claudeSonnetModel: String
    @State private var claudeHaikuModel: String
    @State private var hasAccessGainedAt: Bool
    @State private var accessGainedAt: Date
    @State private var hasAccessDuration: Bool
    @State private var accessDurationValue: String
    @State private var accessDurationUnit: AccountAccessDurationUnit
    @State private var isEnabled: Bool
    @State private var errorMessage: String?

    private let apiKeyProviders = Provider.allCases.filter(\.canAddWithAPIKey)

    init(account: Account) {
        self.account = account
        _provider = State(initialValue: account.provider)
        _label = State(initialValue: account.label)
        _customEndpoint = State(initialValue: account.customEndpoint ?? "")
        _defaultModel = State(initialValue: account.defaultModel ?? "")
        _claudeOpusModel = State(initialValue: account.claudeCodeModelOverrides?.opus ?? "")
        _claudeSonnetModel = State(initialValue: account.claudeCodeModelOverrides?.sonnet ?? "")
        _claudeHaikuModel = State(initialValue: account.claudeCodeModelOverrides?.haiku ?? "")
        _hasAccessGainedAt = State(initialValue: account.accessGainedAt != nil)
        _accessGainedAt = State(initialValue: account.accessGainedAt ?? Date())
        _hasAccessDuration = State(initialValue: account.accessDuration != nil)
        _accessDurationValue = State(initialValue: account.accessDuration.map { String($0.value) } ?? "1")
        _accessDurationUnit = State(initialValue: account.accessDuration?.unit ?? .month)
        _isEnabled = State(initialValue: account.isEnabled)
    }

    private var canEditAPIProfile: Bool {
        account.provider.canAddWithAPIKey
    }

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if hasAccessDuration && parsedAccessDuration == nil { return false }
        if provider.requiresCustomEndpoint {
            return !customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var parsedAccessDuration: AccountAccessDuration? {
        guard hasAccessDuration else { return nil }
        guard let value = Int(accessDurationValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else { return nil }
        return AccountAccessDuration(value: value, unit: accessDurationUnit)
    }

    var body: some View {
        Form {
            Section {
                TextField("Label", text: $label, prompt: Text("e.g. Personal OpenRouter"))
                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Access") {
                Toggle("Track access date", isOn: $hasAccessGainedAt)
                if hasAccessGainedAt {
                    DatePicker(
                        "Gained access",
                        selection: $accessGainedAt,
                        displayedComponents: .date
                    )
                }
                Toggle("Track account period", isOn: $hasAccessDuration)
                if hasAccessDuration {
                    HStack {
                        TextField("Period", text: $accessDurationValue)
                            .frame(width: 72)
                        Picker("Unit", selection: $accessDurationUnit) {
                            ForEach(AccountAccessDurationUnit.allCases) { unit in
                                Text(unit.displayName(for: durationValueForLabel)).tag(unit)
                            }
                        }
                    }
                }
            }

            Section {
                if canEditAPIProfile {
                    Picker("Provider", selection: $provider) {
                        ForEach(apiKeyProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    SecureField("New API Key", text: $apiKey, prompt: Text("Unchanged"))
                    TextField(
                        "Custom Endpoint",
                        text: $customEndpoint,
                        prompt: Text(
                            provider.requiresCustomEndpoint
                                ? "https://api.example.com/v1"
                                : "Optional override"
                        )
                    )
                    TextField("Default Model", text: $defaultModel, prompt: Text(provider.defaultModel ?? "Optional"))
                } else {
                    LabeledContent("Provider", value: provider.displayName)
                    if let defaultModel = account.defaultModel {
                        LabeledContent("Default Model", value: defaultModel)
                    }
                }
            }

            if provider.isClaudeCodeCompatible {
                Section("Claude Code") {
                    ClaudeCodeModelPicker(
                        title: "Opus",
                        selection: $claudeOpusModel,
                        options: claudeCodeModelOptions
                    )
                    ClaudeCodeModelPicker(
                        title: "Sonnet",
                        selection: $claudeSonnetModel,
                        options: claudeCodeModelOptions
                    )
                    ClaudeCodeModelPicker(
                        title: "Haiku",
                        selection: $claudeHaikuModel,
                        options: claudeCodeModelOptions
                    )
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: canEditAPIProfile ? 680 : 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .navigationTitle("Edit Account")
    }

    private func save() {
        do {
            try store.updateProfile(
                accountID: account.id,
                label: label,
                provider: provider,
                customEndpoint: customEndpoint,
                defaultModel: defaultModel,
                accessGainedAt: hasAccessGainedAt ? accessGainedAt : nil,
                accessDuration: parsedAccessDuration,
                isEnabled: isEnabled,
                apiKey: canEditAPIProfile ? apiKey : nil,
                claudeCodeModelOverrides: provider.isClaudeCodeCompatible
                    ? ClaudeCodeModelOverrides.normalized(
                        opus: claudeOpusModel,
                        sonnet: claudeSonnetModel,
                        haiku: claudeHaikuModel
                    )
                    : nil
            )
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private var durationValueForLabel: Int {
        Int(accessDurationValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 2
    }

    private var claudeCodeModelOptions: [ProviderModel] {
        var seen = Set<String>()
        var models: [ProviderModel] = []

        func append(_ model: ProviderModel) {
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            models.append(model)
        }

        if provider == account.provider {
            for model in account.modelCatalog {
                append(model)
            }
        } else {
            for model in provider.bundledModels {
                append(model)
            }
        }

        if let defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            append(ProviderModel(id: defaultModel, name: defaultModel, ownedBy: provider.displayName))
        }

        return models
    }
}

private struct ClaudeCodeModelPicker: View {
    let title: String
    @Binding var selection: String
    let options: [ProviderModel]

    var body: some View {
        if options.isEmpty {
            TextField(title, text: $selection, prompt: Text("Account default"))
        } else {
            Picker(title, selection: $selection) {
                Text("Account default").tag("")
                ForEach(options) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
