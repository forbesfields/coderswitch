import Foundation

actor TokenUsageRecorder {
    private weak var store: AccountStore?

    init(store: AccountStore) {
        self.store = store
    }

    func record(_ event: TokenUsageEvent) async {
        await MainActor.run { [weak store] in
            store?.recordTokenUsage(event)
        }
    }
}
