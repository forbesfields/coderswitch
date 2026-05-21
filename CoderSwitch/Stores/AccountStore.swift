import Foundation
import Observation
import GRDB

@Observable
@MainActor
final class AccountStore {
    private(set) var accounts: [Account] = []

    private let db: DatabaseQueue

    init() {
        self.db = AppDatabase.shared.queue
        load()
        migrateFromJSONIfNeeded()
    }

    func add(_ account: Account, apiKey: String) throws {
        try persist(account, apiKey: apiKey)
        accounts.append(account)
    }

    func syncCodexAccounts(from oauthAccounts: [OAuthAccount]) {
        for oauth in oauthAccounts {
            let alreadyExists = accounts.contains { account in
                account.provider == .codex
                    && (
                        (oauth.externalID != nil && account.externalID == oauth.externalID)
                        || (oauth.email != nil && account.label == oauth.email)
                    )
            }
            guard !alreadyExists else { continue }

            let account = Account(
                id: oauth.id,
                label: oauth.label,
                provider: .codex,
                externalID: oauth.externalID,
                createdAt: oauth.createdAt
            )
            do {
                try persist(account, apiKey: nil)
                accounts.append(account)
            } catch {
                print("AccountStore.syncCodexAccounts failed: \(error)")
            }
        }
    }

    func syncGoogleAntigravityAccounts(from oauthAccounts: [OAuthAccount]) {
        for oauth in oauthAccounts {
            let alreadyExists = accounts.contains { account in
                account.provider == .googleAntigravity
                    && (
                        (oauth.externalID != nil && account.externalID == oauth.externalID)
                        || (oauth.email != nil && account.label == oauth.email)
                    )
            }
            guard !alreadyExists else { continue }

            let account = Account(
                id: oauth.id,
                label: oauth.label,
                provider: .googleAntigravity,
                externalID: oauth.externalID,
                createdAt: oauth.createdAt
            )
            do {
                try persist(account, apiKey: nil)
                accounts.append(account)
            } catch {
                print("AccountStore.syncGoogleAntigravityAccounts failed: \(error)")
            }
        }
    }

    func rename(accountID: UUID, label: String) {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].label = cleaned
        persistMetadata(accounts[idx])
    }

    func delete(_ account: Account) {
        let id = account.id.uuidString
        try? db.write { db in
            try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id])
        }
        accounts.removeAll { $0.id == account.id }
    }

    func apiKey(for account: Account) -> String? {
        let id = account.id.uuidString
        let blob: Data? = try? db.read { db in
            try GRDB.Row.fetchOne(db, sql: "SELECT api_key_encrypted FROM accounts WHERE id = ?", arguments: [id])
                .flatMap { $0["api_key_encrypted"] as Data? }
        } ?? nil
        guard let blob else { return nil }
        return try? SecretBox.open(blob)
    }

    func configExportItems() -> [CoderSwitchConfigAccount] {
        accounts.map { account in
            CoderSwitchConfigAccount(account: account, apiKey: apiKey(for: account))
        }
    }

    func replaceAll(with items: [CoderSwitchConfigAccount]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rows = try items.map { item in
            let json = String(data: try encoder.encode(item.account), encoding: .utf8) ?? "{}"
            let blob = try item.apiKey.map { try SecretBox.seal($0) }
            return (
                id: item.account.id.uuidString,
                json: json,
                apiKey: blob,
                createdAt: Int64(item.account.createdAt.timeIntervalSince1970)
            )
        }

        try db.write { db in
            try db.execute(sql: "DELETE FROM accounts")
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO accounts (id, json, api_key_encrypted, created_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [row.id, row.json, row.apiKey, row.createdAt]
                )
            }
        }
        accounts = items.map(\.account)
    }

    func applyPollResult(
        accountID: UUID,
        limits: [UsageLimit],
        error: String?,
        at date: Date = Date()
    ) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        if error == nil {
            accounts[idx].usageLimits = limits
            if let visibleIDs = accounts[idx].menuBarUsageLimitIDs {
                let availableIDs = Set(limits.map(\.id))
                accounts[idx].menuBarUsageLimitIDs = visibleIDs.intersection(availableIDs)
            }
            accounts[idx].lastCheckError = nil
        } else {
            accounts[idx].lastCheckError = error
        }
        accounts[idx].lastCheckedAt = date
        persistMetadata(accounts[idx])
    }

    func updateModels(accountID: UUID, models: [ProviderModel]) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].availableModels = models
        if accounts[idx].defaultModel == nil {
            accounts[idx].defaultModel = models.first?.id
        }
        persistMetadata(accounts[idx])
    }

    func setDefaultModel(accountID: UUID, modelID: String?) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].defaultModel = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        persistMetadata(accounts[idx])
    }

    func setEnabled(accountID: UUID, isEnabled: Bool) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].isEnabled = isEnabled
        persistMetadata(accounts[idx])
    }

    func setMenuBarUsageLimitVisible(accountID: UUID, limitID: String, isVisible: Bool) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var ids = accounts[idx].menuBarUsageLimitIDs
            ?? Set(accounts[idx].menuBarUsageLimits.map(\.id))
        if isVisible {
            ids.insert(limitID)
        } else {
            ids.remove(limitID)
        }
        accounts[idx].menuBarUsageLimitIDs = ids
        persistMetadata(accounts[idx])
    }

    func setMenuBarUsageLimitIDs(accountID: UUID, limitIDs: Set<String>?) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].menuBarUsageLimitIDs = limitIDs
        persistMetadata(accounts[idx])
    }

    func setCircuitBreaker(accountID: UUID, config: CircuitBreakerConfig) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].circuitBreaker = config
        if !config.enabled {
            accounts[idx].clearFailures()
        }
        persistMetadata(accounts[idx])
    }

    func recordFailure(accountID: UUID, at date: Date = Date()) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].recordFailure(at: date)
        persistMetadata(accounts[idx])
    }

    func clearFailures(accountID: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].clearFailures()
        persistMetadata(accounts[idx])
    }

    func recordTokenUsage(_ event: TokenUsageEvent) {
        guard !event.usage.isEmpty,
              let idx = accounts.firstIndex(where: { $0.id == event.accountID }) else {
            return
        }
        var usage = event.usage
        if usage.requests == 0 {
            usage.requests = 1
        }
        accounts[idx].recordTokenUsage(TokenUsageEvent(
            accountID: event.accountID,
            provider: event.provider,
            model: event.model,
            occurredAt: event.occurredAt,
            usage: usage
        ))
        persistMetadata(accounts[idx])
    }

    func tokenUsageTotal(period: TokenUsagePeriod) -> TokenUsageDelta {
        accounts.reduce(into: TokenUsageDelta()) { total, account in
            total.add(account.tokenUsageTotal(period: period))
        }
    }

    func tokenUsageTotalsByProvider(period: TokenUsagePeriod) -> [TokenUsageGroupTotal] {
        var totals: [Provider: TokenUsageDelta] = [:]
        for account in accounts {
            totals[account.provider, default: TokenUsageDelta()].add(account.tokenUsageTotal(period: period))
        }
        return totals
            .filter { !$0.value.isEmpty }
            .sorted { $0.key.displayName < $1.key.displayName }
            .map {
                TokenUsageGroupTotal(
                    id: $0.key.rawValue,
                    label: $0.key.displayName,
                    totals: $0.value
                )
            }
    }

    func tokenUsageTotalsByModel(period: TokenUsagePeriod) -> [TokenUsageGroupTotal] {
        var totals: [String: TokenUsageDelta] = [:]
        for account in accounts {
            for item in account.tokenUsageTotalsByModel(period: period) {
                let key = "\(account.provider.routingSlug)/\(item.label)"
                totals[key, default: TokenUsageDelta()].add(item.totals)
            }
        }
        return totals
            .filter { !$0.value.isEmpty }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { TokenUsageGroupTotal(id: $0.key, label: $0.key, totals: $0.value) }
    }

    var accountsByProvider: [(Provider, [Account])] {
        Dictionary(grouping: accounts, by: \.provider)
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { ($0.key, $0.value.sorted { $0.label < $1.label }) }
    }

    func tokenUsageDailySeries(period: TokenUsagePeriod, now: Date = Date()) -> [(day: String, totals: TokenUsageDelta)] {
        var byDay: [String: TokenUsageDelta] = [:]
        for account in accounts {
            for bucket in account.tokenUsageBuckets where period.contains(dayKey: bucket.day, now: now) {
                byDay[bucket.day, default: TokenUsageDelta()].add(bucket.totals)
            }
        }
        return byDay
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, totals: $0.value) }
    }

    func tokenUsageByAccount(period: TokenUsagePeriod) -> [(account: Account, totals: TokenUsageDelta)] {
        accounts
            .map { ($0, $0.tokenUsageTotal(period: period)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.1.totalTokens > $1.1.totalTokens }
    }

    private func load() {
        let rows: [(id: String, json: Data, createdAt: Int64)] = (try? db.read { db in
            try GRDB.Row.fetchAll(db, sql: "SELECT id, json, created_at FROM accounts ORDER BY created_at ASC")
                .map { row in
                    (
                        id: row["id"] as String,
                        json: Data((row["json"] as String).utf8),
                        createdAt: row["created_at"] as Int64
                    )
                }
        }) ?? []
        let decoder = JSONDecoder()
        accounts = rows.compactMap { try? decoder.decode(Account.self, from: $0.json) }
    }

    private func persist(_ account: Account, apiKey: String?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(account), encoding: .utf8) ?? "{}"
        let blob = try apiKey.map { try SecretBox.seal($0) }
        let id = account.id.uuidString
        let createdAt = Int64(Date().timeIntervalSince1970)
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, json, api_key_encrypted, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    json = excluded.json,
                    api_key_encrypted = excluded.api_key_encrypted
                """,
                arguments: [id, json, blob, createdAt]
            )
        }
    }

    private func persistMetadata(_ account: Account) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(account),
              let json = String(data: data, encoding: .utf8) else { return }
        let id = account.id.uuidString
        try? db.write { db in
            try db.execute(
                sql: "UPDATE accounts SET json = ? WHERE id = ?",
                arguments: [json, id]
            )
        }
    }

    private func migrateFromJSONIfNeeded() {
        guard accounts.isEmpty else { return }
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoderSwitch", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("accounts.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return
        }
        for account in decoded {
            let key = (try? KeychainStore.getSecret(account: account.id.uuidString)) ?? ""
            do {
                try persist(account, apiKey: key)
                accounts.append(account)
            } catch {
                continue
            }
        }
        try? FileManager.default.removeItem(at: jsonURL)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
