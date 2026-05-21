import Foundation
import Observation
import os

private let quotaLog = Logger(subsystem: "com.coderswitch.proxy", category: "quota")
private let googleAntigravityUserAgent = "antigravity/2.0.1 darwin/arm64"

@Observable
@MainActor
final class QuotaPoller {
    private(set) var isPolling = false
    private(set) var lastRunAt: Date?

    private weak var store: AccountStore?
    private weak var oauthStore: OAuthStore?
    private var timerTask: Task<Void, Never>?

    /// How often to run the full poll cycle.
    var interval: Duration = .seconds(60)

    func bind(store: AccountStore, oauthStore: OAuthStore? = nil) {
        self.store = store
        self.oauthStore = oauthStore
    }

    func start() {
        guard timerTask == nil else { return }
        quotaLog.info("quota poller starting (interval=\(self.interval, privacy: .public))")
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                if Task.isCancelled { break }
                try? await Task.sleep(for: self?.interval ?? .seconds(60))
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    func pollOnce() async {
        guard let store else { return }
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        var standardSnapshots: [(Account, String?, QuotaCheck)] = []
        var codexSnapshots: [(Account, String)] = []
        var antigravitySnapshots: [(Account, String)] = []

        for account in store.accounts where account.isEnabled {
            if account.provider == .codex {
                guard let oauthStore else {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: "missing Codex OAuth store"
                    )
                    continue
                }
                guard let oauth = oauthStore.codexAccount(matching: account) else {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: "missing Codex OAuth account"
                    )
                    continue
                }
                do {
                    let token = try await oauthStore.refreshTokenIfNeeded(for: oauth)
                    codexSnapshots.append((account, token.accessToken))
                } catch {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: error.localizedDescription
                    )
                }
                continue
            }

            if account.provider == .googleAntigravity {
                guard let oauthStore else {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: "missing Google Antigravity OAuth store"
                    )
                    continue
                }
                guard let oauth = oauthStore.geminiAccount(matching: account) else {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: "missing Google Antigravity OAuth account"
                    )
                    continue
                }
                do {
                    let token = try await oauthStore.refreshTokenIfNeeded(for: oauth)
                    antigravitySnapshots.append((account, token.accessToken))
                } catch {
                    store.applyPollResult(
                        accountID: account.id,
                        limits: [],
                        error: error.localizedDescription
                    )
                }
                continue
            }

            guard let check = account.provider.quotaCheck else { continue }
            standardSnapshots.append((account, store.apiKey(for: account), check))
        }

        await withTaskGroup(of: Void.self) { group in
            for (account, apiKey, check) in standardSnapshots {
                group.addTask { [weak self] in
                    await self?.poll(account: account, apiKey: apiKey, check: check)
                }
            }

            for (account, accessToken) in codexSnapshots {
                group.addTask { [weak self] in
                    await self?.pollCodex(account: account, accessToken: accessToken)
                }
            }

            for (account, accessToken) in antigravitySnapshots {
                group.addTask { [weak self] in
                    await self?.pollGoogleAntigravity(account: account, accessToken: accessToken)
                }
            }
        }

        lastRunAt = Date()
    }

    private nonisolated func poll(
        account: Account,
        apiKey: String?,
        check: QuotaCheck
    ) async {
        let result: Result<[UsageLimit], Error>
        do {
            guard let apiKey, !apiKey.isEmpty else {
                throw QuotaCheckError.missingAPIKey
            }
            let url = try check.url(forEndpoint: account.endpoint)
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            for (name, value) in check.headers {
                req.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let limits = try check.parse(data, status)
            result = .success(limits)
        } catch {
            result = .failure(error)
        }

        await MainActor.run { [weak self] in
            switch result {
            case .success(let limits):
                quotaLog.info("quota OK \(account.label, privacy: .public): \(limits.count, privacy: .public) limits")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: limits,
                    error: nil
                )
            case .failure(let error):
                let msg = error.localizedDescription
                quotaLog.error("quota FAIL \(account.label, privacy: .public): \(msg, privacy: .public)")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: [],
                    error: msg
                )
            }
        }
    }

    private nonisolated func pollCodex(account: Account, accessToken: String) async {
        let result: Result<[UsageLimit], Error>
        do {
            let url = try CodexUsageResponse.usageURL(forEndpoint: account.endpoint)
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw QuotaCheckError.httpStatus(status)
            }

            let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            let limits = usage.usageLimits
            guard !limits.isEmpty else {
                throw QuotaCheckError.providerMessage("no Codex quota windows returned")
            }
            result = .success(limits)
        } catch {
            result = .failure(error)
        }

        await MainActor.run { [weak self] in
            switch result {
            case .success(let limits):
                quotaLog.info("codex quota OK \(account.label, privacy: .public): \(limits.count, privacy: .public) limits")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: limits,
                    error: nil
                )
            case .failure(let error):
                let msg = error.localizedDescription
                quotaLog.error("codex quota FAIL \(account.label, privacy: .public): \(msg, privacy: .public)")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: [],
                    error: msg
                )
            }
        }
    }

    private nonisolated func fetchGoogleAntigravityProjectId(accessToken: String) async -> String? {
        let endpoints = [
            "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
            "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
        ]

        let payload: [String: Any] = [
            "clientMetadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]
        let body = try? JSONSerialization.data(withJSONObject: payload)

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(googleAntigravityUserAgent, forHTTPHeaderField: "User-Agent")
            req.httpBody = body

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }
                if let decoded = try? JSONDecoder().decode(AntigravityLoadCodeAssistResponse.self, from: data),
                   let projectId = decoded.cloudaicompanionProject {
                    return projectId
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private nonisolated func pollGoogleAntigravity(account: Account, accessToken: String) async {
        let result: Result<[UsageLimit], Error>
        do {
            let projectId = await fetchGoogleAntigravityProjectId(accessToken: accessToken) ?? ""

            let endpoints = [
                "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
                "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
                "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
            ]

            var lastError: Error = QuotaCheckError.providerMessage("no endpoints attempted")
            var succeeded = false
            var limits: [UsageLimit] = []

            var payloads: [[String: Any]] = [[:]]
            if !projectId.isEmpty {
                payloads.append(["project": projectId])
            }

            for endpoint in endpoints {
                guard let url = URL(string: endpoint) else { continue }
                for payload in payloads {
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 15
                    req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(googleAntigravityUserAgent, forHTTPHeaderField: "User-Agent")
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    do {
                        let (data, response) = try await URLSession.shared.data(for: req)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if status == 401 || status == 403 {
                            lastError = QuotaCheckError.providerMessage(
                                "Google Antigravity authorization was rejected (HTTP \(status)); reconnect this account"
                            )
                            continue
                        } else if status >= 500 {
                            lastError = QuotaCheckError.httpStatus(status)
                            continue
                        } else if status < 200 || status >= 300 && status != 429 {
                            lastError = QuotaCheckError.httpStatus(status)
                            continue
                        }

                        let decoded = try JSONDecoder().decode(AntigravityFetchAvailableModelsResponse.self, from: data)
                        limits = decoded.usageLimits
                        succeeded = true
                        break
                    } catch {
                        lastError = error
                        continue
                    }
                }
                if succeeded { break }
            }

            if succeeded {
                if limits.isEmpty {
                    let existingUserFacingLimits = account.usageLimits.filter { !$0.isGoogleAntigravityInternalModel }
                    if existingUserFacingLimits.isEmpty {
                        result = .failure(QuotaCheckError.providerMessage("no user-facing Google Antigravity model limits returned"))
                    } else {
                        result = .success(existingUserFacingLimits)
                    }
                } else {
                    result = .success(limits)
                }
            } else {
                result = .failure(lastError)
            }
        } catch {
            result = .failure(error)
        }

        await MainActor.run { [weak self] in
            switch result {
            case .success(let limits):
                quotaLog.info("google antigravity quota OK \(account.label, privacy: .public): \(limits.count, privacy: .public) limits")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: limits,
                    error: nil
                )
            case .failure(let error):
                let msg = error.localizedDescription
                quotaLog.error("google antigravity quota FAIL \(account.label, privacy: .public): \(msg, privacy: .public)")
                self?.store?.applyPollResult(
                    accountID: account.id,
                    limits: [],
                    error: msg
                )
            }
        }
    }
}

struct CodexUsageResponse: Decodable {
    private let planType: String?
    private let rateLimit: CodexRateLimit?
    private let credits: CodexCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    static func usageURL(forEndpoint endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/wham/usage") else {
            throw QuotaCheckError.providerMessage("invalid Codex quota endpoint")
        }
        return url
    }

    var usageLimits: [UsageLimit] {
        var limits = [
            rateLimit?.primaryWindow?.usageLimit(name: "5-hour limit"),
            rateLimit?.secondaryWindow?.usageLimit(name: "Weekly limit")
        ].compactMap { $0 }

        if let credits = credits?.usageLimit {
            limits.append(credits)
        }

        return limits
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    var resetDate: Date? {
        resetAt.map { Date(timeIntervalSince1970: $0) }
    }

    func usageLimit(name: String) -> UsageLimit? {
        guard let usedPercent else { return nil }
        return UsageLimit(
            name: name,
            used: usedPercent,
            limit: 100,
            unit: "%",
            resetAt: resetDate
        )
    }
}

private struct CodexCredits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    var usageLimit: UsageLimit? {
        guard hasCredits == true || unlimited == true else { return nil }
        if unlimited == true {
            return UsageLimit(
                name: "Credits",
                used: nil,
                limit: nil,
                unit: nil,
                isPayAsYouGo: true
            )
        }
        guard let balanceValue = balance.flatMap(Double.init) else { return nil }
        return UsageLimit(
            name: "Credits",
            used: balanceValue,
            limit: nil,
            valuePrefix: "$",
            unit: nil,
            isPayAsYouGo: true
        )
    }
}

private struct AntigravityLoadCodeAssistResponse: Decodable {
    let cloudaicompanionProject: String?
}

struct AntigravityFetchAvailableModelsResponse: Decodable {
    let models: [String: AntigravityModelQuotaInfo]?
    let aiCredits: AntigravityCreditsInfo?

    enum CodingKeys: String, CodingKey {
        case models
        case aiCredits = "ai_credits"
    }

    var usageLimits: [UsageLimit] {
        var limits: [UsageLimit] = []
        if let models = models {
            for (modelName, info) in models {
                guard !info.isInternal, !info.isInternalModel(modelID: modelName) else { continue }
                guard let percentageVal = info.remainingFraction else { continue }
                let remainingPercent: Double
                if percentageVal <= 1.0 && percentageVal >= 0.0 {
                    remainingPercent = percentageVal * 100.0
                } else {
                    remainingPercent = percentageVal
                }

                let resetDate = info.resetTimeValue.flatMap { Self.date(from: $0) }
                let displayName = info.userFacingDisplayName(modelID: modelName)

                limits.append(UsageLimit(
                    name: displayName,
                    storageID: modelName,
                    used: min(100, max(0, remainingPercent)),
                    limit: 100,
                    unit: "%",
                    resetAt: resetDate,
                    valueKind: "googleAntigravityRemainingPercent"
                ))
            }
        }

        if let credits = aiCredits {
            let resetDate = Self.date(from: credits.expiryDate)
            limits.append(UsageLimit(
                name: "AI Credits",
                used: credits.credits,
                limit: nil,
                valuePrefix: nil,
                unit: nil,
                resetAt: resetDate,
                isPayAsYouGo: true
            ))
        }

        return limits.sorted { $0.name < $1.name }
    }

    private static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct AntigravityModelQuotaInfo: Decodable {
    let quotaInfo: AntigravityQuotaInfo?
    let percentage: Double?
    let resetTime: String?
    let displayName: String?
    let model: String?
    let isInternal: Bool

    enum CodingKeys: String, CodingKey {
        case quotaInfo
        case percentage
        case resetTime
        case displayName
        case display_name
        case model
        case isInternal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quotaInfo = try container.decodeIfPresent(AntigravityQuotaInfo.self, forKey: .quotaInfo)
        percentage = try container.decodeIfPresent(Double.self, forKey: .percentage)
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        isInternal = try container.decodeIfPresent(Bool.self, forKey: .isInternal) ?? false
    }

    var remainingFraction: Double? {
        quotaInfo?.remainingFraction ?? percentage
    }

    var resetTimeValue: String? {
        quotaInfo?.resetTime ?? resetTime
    }

    func userFacingDisplayName(modelID: String) -> String {
        [displayName, model, modelID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            .first { !Self.isInternalIdentifier($0) }
            ?? modelID
    }

    func isInternalModel(modelID: String) -> Bool {
        Self.isInternalIdentifier(displayName, missingIsInternal: false)
            || Self.isInternalIdentifier(model, missingIsInternal: false)
            || Self.isInternalIdentifier(modelID, missingIsInternal: false)
    }

    private static func isInternalIdentifier(_ value: String?, missingIsInternal: Bool = true) -> Bool {
        guard let value else { return missingIsInternal }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            return missingIsInternal
        }
        return cleaned.hasPrefix("model_placeholder")
            || cleaned.hasPrefix("chat_")
            || cleaned.hasPrefix("tab_")
    }
}

struct AntigravityQuotaInfo: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
}

struct AntigravityCreditsInfo: Decodable {
    let credits: Double
    let expiryDate: String
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
