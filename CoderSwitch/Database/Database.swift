import Foundation
import GRDB

/// Single SQLite database for CoderSwitch.
/// Lives at ~/Library/Application Support/CoderSwitch/coderswitch.sqlite.
/// All persistence (accounts, oauth, proxy, usage) goes through this.
@MainActor
final class AppDatabase {
    static let shared = AppDatabase()

    let queue: DatabaseQueue

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoderSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("coderswitch.sqlite")

        do {
            self.queue = try DatabaseQueue(path: dbURL.path)
            try Self.migrate(self.queue)
        } catch {
            fatalError("CoderSwitch: failed to open database at \(dbURL.path): \(error)")
        }
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY,
                    json TEXT NOT NULL,
                    api_key_encrypted BLOB,
                    created_at INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE oauth_accounts (
                    id TEXT PRIMARY KEY,
                    json TEXT NOT NULL,
                    access_token_encrypted BLOB NOT NULL,
                    refresh_token_encrypted BLOB,
                    created_at INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE proxy_settings (
                    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
                    port INTEGER NOT NULL,
                    admin_key TEXT NOT NULL,
                    auto_start INTEGER NOT NULL
                )
                """)
        }

        migrator.registerMigration("v2_oauth_id_token") { db in
            try db.execute(sql: """
                ALTER TABLE oauth_accounts
                ADD COLUMN id_token_encrypted BLOB
                """)
        }

        migrator.registerMigration("v3_request_logs") { db in
            try db.execute(sql: """
                CREATE TABLE request_logs (
                    id TEXT PRIMARY KEY,
                    timestamp INTEGER NOT NULL,
                    method TEXT NOT NULL,
                    path TEXT NOT NULL,
                    account_id TEXT,
                    account_label TEXT,
                    provider TEXT,
                    model TEXT,
                    upstream_model TEXT,
                    status_code INTEGER,
                    latency_ms INTEGER NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cache_read_tokens INTEGER NOT NULL,
                    cache_write_tokens INTEGER NOT NULL,
                    uncategorized_tokens INTEGER NOT NULL,
                    error_message TEXT
                )
                """)
            try db.execute(sql: """
                CREATE INDEX request_logs_timestamp_idx
                ON request_logs(timestamp DESC)
                """)
        }

        try migrator.migrate(queue)
    }
}
