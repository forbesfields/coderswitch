import Foundation

struct ProxyRequestLog: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let accountID: UUID?
    let accountLabel: String?
    let provider: Provider?
    let model: String?
    let upstreamModel: String?
    let statusCode: Int?
    let latencyMS: Int
    let usage: TokenUsageDelta
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        path: String,
        accountID: UUID?,
        accountLabel: String?,
        provider: Provider?,
        model: String?,
        upstreamModel: String?,
        statusCode: Int?,
        latencyMS: Int,
        usage: TokenUsageDelta = TokenUsageDelta(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.provider = provider
        self.model = model
        self.upstreamModel = upstreamModel
        self.statusCode = statusCode
        self.latencyMS = latencyMS
        self.usage = usage
        self.errorMessage = errorMessage
    }

    var statusSummary: String {
        if let statusCode {
            return "\(statusCode)"
        }
        return errorMessage == nil ? "pending" : "failed"
    }

    var routeSummary: String {
        let account = accountLabel ?? provider?.displayName ?? "Unrouted"
        guard let upstreamModel, !upstreamModel.isEmpty else { return account }
        return "\(account) / \(upstreamModel)"
    }
}
