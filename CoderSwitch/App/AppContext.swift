import Foundation
import Observation

/// Top-level container created exactly once at app launch. Owns the
/// account store, proxy settings, the proxy manager, and the quota
/// poller. Triggers auto-start so the proxy comes up even if the user
/// never opens the popover or settings window.
@MainActor
@Observable
final class AppContext {
    let accountStore: AccountStore
    let proxySettings: ProxySettings
    let proxyManager: ProxyManager
    let quotaPoller: QuotaPoller
    let requestLogStore: RequestLogStore

    init(oauthStore: OAuthStore = .shared) {
        let accountStore = AccountStore()
        let proxySettings = ProxySettings()
        let proxyManager = ProxyManager()
        let quotaPoller = QuotaPoller()
        let requestLogStore = RequestLogStore()
        self.accountStore = accountStore
        self.proxySettings = proxySettings
        self.proxyManager = proxyManager
        self.quotaPoller = quotaPoller
        self.requestLogStore = requestLogStore
        accountStore.syncCodexAccounts(from: oauthStore.accounts(for: .codex))
        accountStore.syncGoogleAntigravityAccounts(from: oauthStore.accounts(for: .gemini))
        proxyManager.bind(accountStore: accountStore, settings: proxySettings, requestLogStore: requestLogStore)
        quotaPoller.bind(store: accountStore, oauthStore: oauthStore)
        guard !Self.isRunningTests else { return }
        if proxySettings.autoStart {
            proxyManager.start()
        }
        quotaPoller.start()
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
