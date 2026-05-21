import Foundation
import Observation
import GRDB

@Observable
@MainActor
final class RequestLogStore {
    private(set) var logs: [ProxyRequestLog] = []

    private let db: DatabaseQueue
    private let maxVisibleLogs = 200
    private let maxPersistedLogs = 2_000

    init() {
        self.db = AppDatabase.shared.queue
        load()
    }

    func record(_ log: ProxyRequestLog) {
        do {
            try persist(log)
            logs.insert(log, at: 0)
            if logs.count > maxVisibleLogs {
                logs.removeLast(logs.count - maxVisibleLogs)
            }
            try prune()
        } catch {
            print("RequestLogStore.record failed: \(error)")
        }
    }

    func clear() {
        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM request_logs")
            }
            logs.removeAll()
        } catch {
            print("RequestLogStore.clear failed: \(error)")
        }
    }

    private func load() {
        logs = (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT *
                FROM request_logs
                ORDER BY timestamp DESC
                LIMIT ?
                """, arguments: [maxVisibleLogs]).compactMap(Self.decode)
        }) ?? []
    }

    private func persist(_ log: ProxyRequestLog) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO request_logs (
                    id,
                    timestamp,
                    method,
                    path,
                    account_id,
                    account_label,
                    provider,
                    model,
                    upstream_model,
                    status_code,
                    latency_ms,
                    input_tokens,
                    output_tokens,
                    cache_read_tokens,
                    cache_write_tokens,
                    uncategorized_tokens,
                    error_message
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    log.id.uuidString,
                    Int64(log.timestamp.timeIntervalSince1970 * 1000),
                    log.method,
                    log.path,
                    log.accountID?.uuidString,
                    log.accountLabel,
                    log.provider?.rawValue,
                    log.model,
                    log.upstreamModel,
                    log.statusCode,
                    log.latencyMS,
                    log.usage.inputTokens,
                    log.usage.outputTokens,
                    log.usage.cacheReadTokens,
                    log.usage.cacheWriteTokens,
                    log.usage.uncategorizedTokens,
                    log.errorMessage
                ]
            )
        }
    }

    private func prune() throws {
        try db.write { db in
            try db.execute(sql: """
                DELETE FROM request_logs
                WHERE id NOT IN (
                    SELECT id
                    FROM request_logs
                    ORDER BY timestamp DESC
                    LIMIT ?
                )
                """, arguments: [maxPersistedLogs])
        }
    }

    private static func decode(_ row: Row) -> ProxyRequestLog? {
        guard let id = UUID(uuidString: row["id"] as String),
              let timestampMS = row["timestamp"] as Int64? else {
            return nil
        }
        let accountIDString = row["account_id"] as String?
        let providerRaw = row["provider"] as String?
        return ProxyRequestLog(
            id: id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestampMS) / 1000),
            method: row["method"] as String,
            path: row["path"] as String,
            accountID: accountIDString.flatMap(UUID.init(uuidString:)),
            accountLabel: row["account_label"] as String?,
            provider: providerRaw.flatMap(Provider.init(rawValue:)),
            model: row["model"] as String?,
            upstreamModel: row["upstream_model"] as String?,
            statusCode: row["status_code"] as Int?,
            latencyMS: row["latency_ms"] as Int,
            usage: TokenUsageDelta(
                inputTokens: row["input_tokens"] as Int,
                outputTokens: row["output_tokens"] as Int,
                cacheReadTokens: row["cache_read_tokens"] as Int,
                cacheWriteTokens: row["cache_write_tokens"] as Int,
                uncategorizedTokens: row["uncategorized_tokens"] as Int
            ),
            errorMessage: row["error_message"] as String?
        )
    }
}
