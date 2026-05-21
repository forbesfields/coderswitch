import Foundation

struct TokenUsageDelta: Codable, Hashable, Sendable {
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var uncategorizedTokens: Int

    init(
        requests: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        uncategorizedTokens: Int = 0
    ) {
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.uncategorizedTokens = uncategorizedTokens
    }

    var totalTokens: Int {
        inputTokens + outputTokens + uncategorizedTokens
    }

    var isEmpty: Bool {
        requests == 0
            && inputTokens == 0
            && outputTokens == 0
            && cacheReadTokens == 0
            && cacheWriteTokens == 0
            && uncategorizedTokens == 0
    }

    mutating func add(_ other: TokenUsageDelta) {
        requests += other.requests
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheWriteTokens += other.cacheWriteTokens
        uncategorizedTokens += other.uncategorizedTokens
    }

    mutating func mergeMax(_ other: TokenUsageDelta) {
        inputTokens = max(inputTokens, other.inputTokens)
        outputTokens = max(outputTokens, other.outputTokens)
        cacheReadTokens = max(cacheReadTokens, other.cacheReadTokens)
        cacheWriteTokens = max(cacheWriteTokens, other.cacheWriteTokens)
        uncategorizedTokens = max(uncategorizedTokens, other.uncategorizedTokens)
    }
}

struct TokenUsageBucket: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(day)|\(model)" }
    var day: String
    var model: String
    var totals: TokenUsageDelta
}

struct TokenUsageEvent: Hashable, Sendable {
    let accountID: UUID
    let provider: Provider
    let model: String
    let occurredAt: Date
    let usage: TokenUsageDelta
}

enum TokenUsagePeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: "Today"
        case .week: "This Week"
        case .month: "This Month"
        case .year: "This Year"
        case .allTime: "All Time"
        }
    }

    func contains(dayKey: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .allTime else { return true }
        guard let date = Self.date(from: dayKey, calendar: calendar) else { return false }
        switch self {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) ?? false
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .allTime:
            return true
        }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

struct TokenUsageGroupTotal: Identifiable, Sendable {
    let id: String
    let label: String
    let totals: TokenUsageDelta
}

struct TokenUsageParser: Sendable {
    static func parseJSONResponse(_ data: Data) -> TokenUsageDelta? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseUsageEnvelope(object)
    }

    static func parseSSEEvent(_ event: String) -> TokenUsageDelta? {
        var best = TokenUsageDelta()
        for line in event.split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let usage = parseUsageEnvelope(object) else {
                continue
            }
            best.mergeMax(usage)
        }
        return best.isEmpty ? nil : best
    }

    private static func parseUsageEnvelope(_ object: [String: Any]) -> TokenUsageDelta? {
        if let usage = object["usage"] as? [String: Any] {
            return parseUsage(usage)
        }
        if let message = object["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            return parseUsage(usage)
        }
        if let response = object["response"] as? [String: Any],
           let usage = response["usage"] as? [String: Any] {
            return parseUsage(usage)
        }
        return nil
    }

    private static func parseUsage(_ usage: [String: Any]) -> TokenUsageDelta? {
        let input = intValue(usage["prompt_tokens"]) ?? intValue(usage["input_tokens"]) ?? 0
        let output = intValue(usage["completion_tokens"]) ?? intValue(usage["output_tokens"]) ?? 0
        let total = intValue(usage["total_tokens"])

        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        let inputDetails = usage["input_token_details"] as? [String: Any]
            ?? usage["input_tokens_details"] as? [String: Any]
        let cacheRead = intValue(usage["cache_read_input_tokens"])
            ?? intValue(usage["cache_read_tokens"])
            ?? intValue(promptDetails?["cached_tokens"])
            ?? intValue(inputDetails?["cache_read"])
            ?? intValue(inputDetails?["cached_tokens"])
            ?? 0
        let cacheWrite = intValue(usage["cache_creation_input_tokens"])
            ?? intValue(usage["cache_write_tokens"])
            ?? intValue(promptDetails?["cache_creation_tokens"])
            ?? intValue(inputDetails?["cache_write"])
            ?? 0

        let knownTotal = input + output
        let uncategorized = input == 0 && output == 0 ? (total ?? 0) : max(0, (total ?? knownTotal) - knownTotal)
        let delta = TokenUsageDelta(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            uncategorizedTokens: uncategorized
        )
        return delta.isEmpty ? nil : delta
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            int
        case let double as Double:
            Int(double)
        case let number as NSNumber:
            number.intValue
        case let string as String:
            Int(string)
        default:
            nil
        }
    }
}
