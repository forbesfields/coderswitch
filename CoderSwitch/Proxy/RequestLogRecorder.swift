import Foundation

actor RequestLogRecorder {
    private weak var store: RequestLogStore?

    init(store: RequestLogStore) {
        self.store = store
    }

    func record(_ log: ProxyRequestLog) async {
        await MainActor.run { [weak store] in
            store?.record(log)
        }
    }
}
