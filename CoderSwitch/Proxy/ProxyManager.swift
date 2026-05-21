import Foundation
import Observation
import os

private let proxyLog = Logger(subsystem: "com.coderswitch.proxy", category: "manager")

@Observable
@MainActor
final class ProxyManager {
    enum Status: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case stopping
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private(set) var status: Status = .stopped

    private let state = ProxyState()
    private var task: Task<Void, Never>?
    private var usageRecorder: TokenUsageRecorder?
    private var requestLogRecorder: RequestLogRecorder?

    private weak var accountStore: AccountStore?
    private var settings: ProxySettings?

    func bind(accountStore: AccountStore, settings: ProxySettings, requestLogStore: RequestLogStore) {
        guard self.accountStore !== accountStore else { return }
        self.accountStore = accountStore
        self.settings = settings
        let usageRecorder = TokenUsageRecorder(store: accountStore)
        let requestLogRecorder = RequestLogRecorder(store: requestLogStore)
        self.usageRecorder = usageRecorder
        self.requestLogRecorder = requestLogRecorder
        Task { await self.state.setUsageRecorder(usageRecorder) }
        Task { await self.state.setRequestLogRecorder(requestLogRecorder) }
        Task { [weak accountStore] in
            await self.state.setFailureRecorder { id in
                Task { @MainActor in
                    accountStore?.recordFailure(accountID: id)
                }
            }
        }
        Task { await self.refreshState() }
        observeChanges()
    }

    private func observeChanges() {
        guard let store = accountStore, let settings else { return }
        withObservationTracking {
            _ = store.accounts
            _ = settings.adminKey
            _ = settings.port
        } onChange: {
            Task { @MainActor [weak self] in
                await self?.refreshState()
                self?.observeChanges()
            }
        }
    }

    func refreshState() async {
        guard let store = accountStore, let settings = settings else { return }
        let accounts = store.accounts
        var keys: [UUID: String] = [:]
        for account in accounts {
            if let key = store.apiKey(for: account) {
                keys[account.id] = key
            }
        }
        let adminKey = settings.adminKey
        await state.update(accounts: accounts, apiKeys: keys, adminKey: adminKey)
        proxyLog.info("state refresh: accounts=\(accounts.count, privacy: .public) keyed=\(keys.count, privacy: .public) adminKeyConfigured=\(!adminKey.isEmpty, privacy: .public)")
    }

    func start() {
        guard let settings else {
            proxyLog.error("start() called before bind() — refusing")
            status = .failed("not bound")
            return
        }
        if task != nil {
            proxyLog.notice("start() ignored — task already running (status=\(String(describing: self.status), privacy: .public))")
            return
        }
        let port = settings.port
        proxyLog.info("start() requested on port \(port, privacy: .public)")
        FileHandle.standardError.write(Data("[CoderSwitch] proxy starting on 127.0.0.1:\(port)\n".utf8))
        status = .starting
        let server = ProxyServer(port: port, state: state)
        task = Task { [weak self] in
            FileHandle.standardError.write(Data("[CoderSwitch] task entered → calling runService on :\(port)\n".utf8))
            do {
                proxyLog.info("hummingbird runService → bind 127.0.0.1:\(port, privacy: .public)")
                try await server.runUntilCancelled()
                FileHandle.standardError.write(Data("[CoderSwitch] runService returned cleanly\n".utf8))
                await MainActor.run { self?.status = .stopped }
            } catch is CancellationError {
                FileHandle.standardError.write(Data("[CoderSwitch] runService cancelled\n".utf8))
                await MainActor.run { self?.status = .stopped }
            } catch {
                let msg = "\(type(of: error)): \(error.localizedDescription)"
                FileHandle.standardError.write(Data("[CoderSwitch] runService failed: \(msg)\n".utf8))
                await MainActor.run { self?.status = .failed(msg) }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                guard let self else { return }
                if case .starting = self.status {
                    self.status = .running(port: port)
                    proxyLog.info("status → running(port: \(port, privacy: .public))")
                }
            }
        }
    }

    func stop() {
        guard let task else {
            proxyLog.notice("stop() ignored — no running task")
            return
        }
        proxyLog.info("stop() requested")
        status = .stopping
        task.cancel()
        self.task = nil
    }

    func restart() {
        proxyLog.info("restart() requested")
        stop()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.start()
        }
    }
}
