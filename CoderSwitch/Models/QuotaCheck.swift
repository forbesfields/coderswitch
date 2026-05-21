import Foundation

/// Describes how to fetch usage/quota for a provider. nil = no public quota endpoint we trust.
struct QuotaCheck: Sendable {
    let path: String
    let headers: [String: String]
    let makeURL: @Sendable (_ endpoint: String, _ path: String) throws -> URL
    /// Parses a `(data, statusCode)` pair into UsageLimits.
    let parse: @Sendable (Data, Int) throws -> [UsageLimit]

    init(
        path: String,
        headers: [String: String] = [:],
        makeURL: @escaping @Sendable (_ endpoint: String, _ path: String) throws -> URL = QuotaCheck.defaultURL,
        parse: @escaping @Sendable (Data, Int) throws -> [UsageLimit]
    ) {
        self.path = path
        self.headers = headers
        self.makeURL = makeURL
        self.parse = parse
    }

    func url(forEndpoint endpoint: String) throws -> URL {
        try makeURL(endpoint, path)
    }
}

extension Provider {
    /// Slug used as a model prefix to route to this provider type.
    /// Duplicated in ModelRouter; this version is the canonical home.
    var quotaCheck: QuotaCheck? {
        switch self {
        case .openRouter: return .openRouter
        case .miniMax: return .miniMax
        default: return nil
        }
    }
}

extension QuotaCheck {
    static func defaultURL(endpoint: String, path: String) throws -> URL {
        var trimmed = endpoint
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: trimmed + normalizedPath) else {
            throw URLError(.badURL)
        }
        return url
    }

    static let openRouter = QuotaCheck(
        path: "/credits",
        parse: { data, status in
            guard status == 200 else {
                throw QuotaCheckError.httpStatus(status)
            }
            let decoded = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
            let d = decoded.data
            let balance = d.total_credits - d.total_usage
            return [
                UsageLimit(
                    name: "Balance",
                    used: balance,
                    limit: nil,
                    valuePrefix: "$",
                    unit: nil,
                    resetAt: nil,
                    isPayAsYouGo: true
                )
            ]
        }
    )

    static let miniMax = QuotaCheck(
        path: "/v1/token_plan/remains",
        headers: [
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://platform.minimax.io/user-center/payment/token-plan"
        ],
        makeURL: { endpoint, path in
            guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw URLError(.badURL)
            }
            components.path = path
            components.query = nil
            components.fragment = nil
            guard let url = components.url else {
                throw URLError(.badURL)
            }
            return url
        },
        parse: { data, status in
            guard status == 200 else {
                throw QuotaCheckError.httpStatus(status)
            }
            let decoded = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: data)
            if let baseResp = decoded.base_resp, let code = baseResp.status_code, code != 0 {
                throw QuotaCheckError.providerMessage(baseResp.status_msg ?? "MiniMax API error \(code)")
            }

            var limits: [UsageLimit] = []
            for remain in decoded.model_remains ?? [] {
                guard let modelName = remain.model_name?.nonEmpty,
                      modelName.hasPrefix("MiniMax-M") else { continue }
                appendCountLimit(
                    to: &limits,
                    name: modelName,
                    total: remain.current_interval_total_count,
                    usedCandidates: [
                        remain.current_interval_used_count,
                        remain.current_interval_usage_count
                    ],
                    remainingCandidates: [
                        remain.current_interval_remaining_count,
                        remain.current_interval_remains_count
                    ],
                    resetAt: remain.resetAt
                )
                appendCountLimit(
                    to: &limits,
                    name: "\(modelName) weekly",
                    total: remain.weekly_total_count ?? remain.current_week_total_count,
                    usedCandidates: [
                        remain.weekly_used_count,
                        remain.weekly_usage_count,
                        remain.current_week_used_count,
                        remain.current_week_usage_count
                    ],
                    remainingCandidates: [
                        remain.weekly_remaining_count,
                        remain.weekly_remains_count,
                        remain.current_week_remaining_count,
                        remain.current_week_remains_count
                    ],
                    resetAt: remain.weeklyResetAt
                )
            }

            guard !limits.isEmpty else {
                throw QuotaCheckError.unparseableResponse
            }
            return limits
        }
    )

    private static func appendCountLimit(
        to limits: inout [UsageLimit],
        name: String,
        total: Double?,
        usedCandidates: [Double?],
        remainingCandidates: [Double?],
        resetAt: Date?
    ) {
        guard let total else { return }
        let used: Double
        if let directUsed = usedCandidates.compactMap({ $0 }).first {
            used = directUsed
        } else if let remaining = remainingCandidates.compactMap({ $0 }).first {
            used = max(0, total - remaining)
        } else {
            return
        }
        limits.append(UsageLimit(
            name: name,
            used: max(0, used),
            limit: total,
            unit: " requests",
            resetAt: resetAt,
            valueKind: "minimaxRemainingNormalized"
        ))
    }
}

enum QuotaCheckError: LocalizedError {
    case httpStatus(Int)
    case missingAPIKey
    case providerMessage(String)
    case unparseableResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let s): return "HTTP \(s)"
        case .missingAPIKey: return "no API key"
        case .providerMessage(let message): return message
        case .unparseableResponse: return "could not parse quota response"
        }
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    struct Data: Decodable {
        let total_credits: Double
        let total_usage: Double
    }
    let data: Data
}

private struct MiniMaxRemainsResponse: Decodable {
    let model_remains: [MiniMaxModelRemain]?
    let base_resp: MiniMaxBaseResponse?
}

private struct MiniMaxBaseResponse: Decodable {
    let status_code: Int?
    let status_msg: String?
}

private struct MiniMaxModelRemain: Decodable {
    let model_name: String?
    let start_time: Double?
    let end_time: Double?
    let remains_time: Double?

    let current_interval_total_count: Double?
    let current_interval_usage_count: Double?
    let current_interval_remaining_count: Double?
    let current_interval_remains_count: Double?
    let current_interval_used_count: Double?

    let weekly_total_count: Double?
    let weekly_usage_count: Double?
    let weekly_remaining_count: Double?
    let weekly_remains_count: Double?
    let weekly_used_count: Double?
    let weekly_end_time: Double?
    let weekly_reset_time: Double?

    let current_week_total_count: Double?
    let current_week_usage_count: Double?
    let current_week_remaining_count: Double?
    let current_week_remains_count: Double?
    let current_week_used_count: Double?
    let current_week_end_time: Double?
    let current_week_reset_time: Double?

    var resetAt: Date? {
        Self.date(fromEpoch: end_time)
            ?? Self.date(fromDurationFromNow: remains_time)
    }

    var weeklyResetAt: Date? {
        Self.date(fromEpoch: weekly_reset_time)
            ?? Self.date(fromEpoch: weekly_end_time)
            ?? Self.date(fromEpoch: current_week_reset_time)
            ?? Self.date(fromEpoch: current_week_end_time)
    }

    private static func date(fromEpoch value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func date(fromDurationFromNow value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 100_000 ? value / 1000 : value
        return Date(timeIntervalSinceNow: seconds)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
