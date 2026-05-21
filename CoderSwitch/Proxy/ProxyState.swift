import Foundation

/// Sendable snapshot of state needed by the proxy server's request handlers.
/// Updated by the MainActor app whenever accounts/keys/settings change.
actor ProxyState {
    private(set) var accounts: [Account] = []
    private(set) var apiKeys: [UUID: String] = [:]
    private(set) var adminKey: String = ""
    private var usageRecorder: TokenUsageRecorder?
    private var requestLogRecorder: RequestLogRecorder?
    private var failureRecorder: (@Sendable (UUID) -> Void)?

    func update(accounts: [Account], apiKeys: [UUID: String], adminKey: String) {
        self.accounts = accounts
        self.apiKeys = apiKeys
        self.adminKey = adminKey
    }

    func setUsageRecorder(_ usageRecorder: TokenUsageRecorder) {
        self.usageRecorder = usageRecorder
    }

    func setRequestLogRecorder(_ requestLogRecorder: RequestLogRecorder) {
        self.requestLogRecorder = requestLogRecorder
    }

    func setFailureRecorder(_ recorder: @escaping @Sendable (UUID) -> Void) {
        self.failureRecorder = recorder
    }

    func recordUsage(_ event: TokenUsageEvent) async {
        await usageRecorder?.record(event)
    }

    func recordRequestLog(_ log: ProxyRequestLog) async {
        await requestLogRecorder?.record(log)
    }

    func recordFailure(accountID: UUID) {
        failureRecorder?(accountID)
    }

    struct Snapshot: Sendable {
        let accounts: [Account]
        let apiKeys: [UUID: String]
        let adminKey: String
    }

    func snapshot() -> Snapshot {
        Snapshot(accounts: accounts, apiKeys: apiKeys, adminKey: adminKey)
    }
}
