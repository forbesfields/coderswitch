import Foundation

struct Account: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var label: String
    var provider: Provider
    var customEndpoint: String?
    var externalID: String?
    var defaultModel: String?
    var availableModels: [ProviderModel]?
    let createdAt: Date
    var usageLimits: [UsageLimit]
    var lastCheckedAt: Date?
    var lastCheckError: String?
    var tokenUsageBuckets: [TokenUsageBucket]
    var circuitBreaker: CircuitBreakerConfig
    var recentFailures: [Date]
    var isEnabled: Bool
    var menuBarUsageLimitIDs: Set<String>?

    init(
        id: UUID = UUID(),
        label: String,
        provider: Provider,
        customEndpoint: String? = nil,
        externalID: String? = nil,
        defaultModel: String? = nil,
        availableModels: [ProviderModel]? = nil,
        createdAt: Date = Date(),
        usageLimits: [UsageLimit] = [],
        lastCheckedAt: Date? = nil,
        lastCheckError: String? = nil,
        tokenUsageBuckets: [TokenUsageBucket] = [],
        circuitBreaker: CircuitBreakerConfig = .init(),
        recentFailures: [Date] = [],
        isEnabled: Bool = true,
        menuBarUsageLimitIDs: Set<String>? = nil
    ) {
        self.id = id
        self.label = label
        self.provider = provider
        self.customEndpoint = customEndpoint
        self.externalID = externalID
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.createdAt = createdAt
        self.usageLimits = usageLimits
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckError = lastCheckError
        self.tokenUsageBuckets = tokenUsageBuckets
        self.circuitBreaker = circuitBreaker
        self.recentFailures = recentFailures
        self.isEnabled = isEnabled
        self.menuBarUsageLimitIDs = menuBarUsageLimitIDs
    }

    var endpoint: String {
        customEndpoint?.trimmingCharacters(in: .whitespaces).nonEmpty
            ?? provider.defaultEndpoint
    }

    func tokenUsageTotal(
        period: TokenUsagePeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenUsageDelta {
        tokenUsageBuckets.reduce(into: TokenUsageDelta()) { total, bucket in
            guard period.contains(dayKey: bucket.day, now: now, calendar: calendar) else { return }
            total.add(bucket.totals)
        }
    }

    func tokenUsageTotalsByModel(
        period: TokenUsagePeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TokenUsageGroupTotal] {
        var totals: [String: TokenUsageDelta] = [:]
        for bucket in tokenUsageBuckets where period.contains(dayKey: bucket.day, now: now, calendar: calendar) {
            totals[bucket.model, default: TokenUsageDelta()].add(bucket.totals)
        }
        return totals
            .filter { !$0.value.isEmpty }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { TokenUsageGroupTotal(id: $0.key, label: $0.key, totals: $0.value) }
    }

    mutating func recordTokenUsage(_ event: TokenUsageEvent) {
        let model = event.model.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "unknown"
        let day = TokenUsagePeriod.dayKey(for: event.occurredAt)
        if let idx = tokenUsageBuckets.firstIndex(where: { $0.day == day && $0.model == model }) {
            tokenUsageBuckets[idx].totals.add(event.usage)
        } else {
            tokenUsageBuckets.append(TokenUsageBucket(day: day, model: model, totals: event.usage))
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case provider
        case customEndpoint
        case externalID
        case defaultModel
        case availableModels
        case createdAt
        case usageLimits
        case lastCheckedAt
        case lastCheckError
        case tokenUsageBuckets
        case circuitBreaker
        case recentFailures
        case isEnabled
        case menuBarUsageLimitIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        let decodedProvider = try Self.decodeProvider(from: container)
        provider = decodedProvider.provider
        customEndpoint = try container.decodeIfPresent(String.self, forKey: .customEndpoint)
            ?? decodedProvider.legacyEndpoint
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        availableModels = try container.decodeIfPresent([ProviderModel].self, forKey: .availableModels)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedUsageLimits = try container.decodeIfPresent([UsageLimit].self, forKey: .usageLimits) ?? []
        usageLimits = provider == .miniMax
            ? decodedUsageLimits.map(Self.normalizeLegacyMiniMaxLimit)
            : decodedUsageLimits
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastCheckError = try container.decodeIfPresent(String.self, forKey: .lastCheckError)
        tokenUsageBuckets = try container.decodeIfPresent([TokenUsageBucket].self, forKey: .tokenUsageBuckets) ?? []
        circuitBreaker = try container.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker) ?? CircuitBreakerConfig()
        recentFailures = try container.decodeIfPresent([Date].self, forKey: .recentFailures) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        menuBarUsageLimitIDs = try container.decodeIfPresent(Set<String>.self, forKey: .menuBarUsageLimitIDs)
    }

    var menuBarUsageLimits: [UsageLimit] {
        guard provider == .googleAntigravity else { return usageLimits }
        guard let menuBarUsageLimitIDs else {
            return Array(usageLimits.filter { !$0.isGoogleAntigravityInternalModel }.prefix(3))
        }
        return usageLimits.filter { menuBarUsageLimitIDs.contains($0.id) && !$0.isGoogleAntigravityInternalModel }
    }

    /// Whether to show a warning to the user — never blocks routing.
    func shouldWarnAboutFailures(now: Date = Date()) -> Bool {
        guard circuitBreaker.enabled else { return false }
        let cutoff = now.addingTimeInterval(-circuitBreaker.windowSeconds)
        return recentFailures.filter { $0 >= cutoff }.count >= circuitBreaker.failureThreshold
    }

    mutating func recordFailure(at date: Date = Date()) {
        let cutoff = date.addingTimeInterval(-circuitBreaker.windowSeconds)
        recentFailures.append(date)
        recentFailures.removeAll { $0 < cutoff }
    }

    mutating func clearFailures() {
        recentFailures.removeAll()
    }

    private static func normalizeLegacyMiniMaxLimit(_ limit: UsageLimit) -> UsageLimit {
        guard limit.valueKind != "minimaxRemainingNormalized",
              limit.name.hasPrefix("MiniMax-M"),
              limit.unit?.contains("request") == true,
              let used = limit.used,
              let total = limit.limit,
              total > 0 else {
            return limit
        }

        var normalized = limit
        if used > total - used {
            normalized.used = max(0, total - used)
        }
        normalized.valueKind = "minimaxRemainingNormalized"
        return normalized
    }

    private static func decodeProvider(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> (provider: Provider, legacyEndpoint: String?) {
        let rawProvider = try container.decode(String.self, forKey: .provider)
        if let provider = Provider(rawValue: rawProvider) {
            return (provider, nil)
        }

        switch rawProvider {
        case "ikunCode":
            return (.openAICompatible, "https://api.ikuncode.cc/v1")
        case "fishXCode":
            return (.openAICompatible, "https://api.fishxcode.com/v1")
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Unsupported provider '\(rawProvider)'"
            )
        }
    }
}

struct CircuitBreakerConfig: Codable, Hashable, Sendable {
    var enabled: Bool
    var failureThreshold: Int
    var windowSeconds: TimeInterval

    init(enabled: Bool = false, failureThreshold: Int = 5, windowSeconds: TimeInterval = 300) {
        self.enabled = enabled
        self.failureThreshold = failureThreshold
        self.windowSeconds = windowSeconds
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
