import Foundation
import NIOCore

struct UsageTrackingStream: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    let base: UpstreamForwarder.ByteStream
    let state: ProxyState
    let accountID: UUID
    let provider: Provider
    let model: String
    let contentType: String?
    let requestLogContext: ProxyRequestLogContext?

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: UpstreamForwarder.ByteStream.AsyncIterator
        let state: ProxyState
        let accountID: UUID
        let provider: Provider
        let model: String
        var collector: UsageResponseCollector
        let requestLogContext: ProxyRequestLogContext?
        var didRecord = false

        mutating func next() async throws -> ByteBuffer? {
            do {
                guard let chunk = try await base.next() else {
                    await recordIfNeeded()
                    return nil
                }
                collector.consume(chunk)
                return chunk
            } catch {
                await recordIfNeeded(errorMessage: error.localizedDescription)
                throw error
            }
        }

        private mutating func recordIfNeeded(errorMessage: String? = nil) async {
            guard !didRecord else { return }
            didRecord = true
            var usage = collector.finish() ?? TokenUsageDelta()
            if !usage.isEmpty {
                if usage.requests == 0 {
                    usage.requests = 1
                }
                await state.recordUsage(TokenUsageEvent(
                    accountID: accountID,
                    provider: provider,
                    model: model,
                    occurredAt: Date(),
                    usage: usage
                ))
            }

            if let requestLogContext {
                let latencyMS = Swift.max(0, Int(Date().timeIntervalSince(requestLogContext.startedAt) * 1000))
                await state.recordRequestLog(ProxyRequestLog(
                    timestamp: requestLogContext.startedAt,
                    method: requestLogContext.method,
                    path: requestLogContext.path,
                    accountID: accountID,
                    accountLabel: requestLogContext.accountLabel,
                    provider: provider,
                    model: requestLogContext.requestedModel,
                    upstreamModel: model,
                    statusCode: requestLogContext.statusCode,
                    latencyMS: latencyMS,
                    usage: usage,
                    errorMessage: errorMessage
                ))
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: base.makeAsyncIterator(),
            state: state,
            accountID: accountID,
            provider: provider,
            model: model,
            collector: UsageResponseCollector(contentType: contentType),
            requestLogContext: requestLogContext
        )
    }
}

struct ProxyRequestLogContext: Sendable {
    let startedAt: Date
    let method: String
    let path: String
    let accountLabel: String
    let requestedModel: String
    let statusCode: Int
}

struct UsageResponseCollector: Sendable {
    private let isEventStream: Bool
    private var sseBuffer = ""
    private var jsonBuffer = Data()
    private var bestStreamingUsage = TokenUsageDelta()
    private let maxJSONBytes = 16 * 1024 * 1024

    init(contentType: String?) {
        isEventStream = contentType?.lowercased().contains("text/event-stream") == true
    }

    mutating func consume(_ buffer: ByteBuffer) {
        let data = Data(buffer: buffer)
        if isEventStream {
            sseBuffer += String(decoding: data, as: UTF8.self)
            parseCompleteSSEEvents()
        } else if jsonBuffer.count + data.count <= maxJSONBytes {
            jsonBuffer.append(data)
        }
    }

    mutating func finish() -> TokenUsageDelta? {
        if isEventStream {
            if !sseBuffer.isEmpty {
                parseSSEEvent(sseBuffer)
                sseBuffer.removeAll(keepingCapacity: false)
            }
            return bestStreamingUsage.isEmpty ? nil : bestStreamingUsage
        }
        return TokenUsageParser.parseJSONResponse(jsonBuffer)
    }

    private mutating func parseCompleteSSEEvents() {
        while let range = nextSSEDelimiterRange() {
            let event = String(sseBuffer[..<range.lowerBound])
            parseSSEEvent(event)
            sseBuffer.removeSubrange(sseBuffer.startIndex..<range.upperBound)
        }
    }

    private mutating func parseSSEEvent(_ event: String) {
        guard let usage = TokenUsageParser.parseSSEEvent(event) else { return }
        bestStreamingUsage.mergeMax(usage)
    }

    private func nextSSEDelimiterRange() -> Range<String.Index>? {
        let lf = sseBuffer.range(of: "\n\n")
        let crlf = sseBuffer.range(of: "\r\n\r\n")
        switch (lf, crlf) {
        case (.some(let a), .some(let b)):
            return a.lowerBound < b.lowerBound ? a : b
        case (.some(let range), nil), (nil, .some(let range)):
            return range
        case (nil, nil):
            return nil
        }
    }
}
