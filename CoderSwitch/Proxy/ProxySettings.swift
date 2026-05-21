import Foundation
import Observation
import GRDB

@Observable
@MainActor
final class ProxySettings {
    var port: Int {
        didSet { save() }
    }
    var adminKey: String {
        didSet { save() }
    }
    var autoStart: Bool {
        didSet { save() }
    }

    private let db: DatabaseQueue

    init() {
        self.db = AppDatabase.shared.queue

        if let stored = Self.load(from: db) {
            self.port = stored.port
            self.adminKey = stored.adminKey
            self.autoStart = stored.autoStart
        } else if let migrated = Self.migrateFromJSON() {
            self.port = migrated.port
            self.adminKey = migrated.adminKey
            self.autoStart = migrated.autoStart
            save()
        } else {
            self.port = 8484
            self.adminKey = Self.generateKey()
            self.autoStart = false
            save()
        }
    }

    var baseURL: String { "http://127.0.0.1:\(port)" }

    var configExportItem: CoderSwitchConfigProxySettings {
        CoderSwitchConfigProxySettings(
            port: port,
            adminKey: adminKey,
            autoStart: autoStart
        )
    }

    func applyConfigImport(_ imported: CoderSwitchConfigProxySettings) {
        port = imported.port
        adminKey = imported.adminKey
        autoStart = imported.autoStart
    }

    func resetToDefaults() {
        port = 8484
        adminKey = Self.generateKey()
        autoStart = false
    }

    private static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "cs-" + Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func regenerateKey() {
        adminKey = Self.generateKey()
    }

    private struct Row {
        let port: Int
        let adminKey: String
        let autoStart: Bool
    }

    private static func load(from db: DatabaseQueue) -> Row? {
        try? db.read { db in
            try GRDB.Row.fetchOne(db, sql: "SELECT port, admin_key, auto_start FROM proxy_settings WHERE id = 1")
                .map { row in
                    Row(
                        port: row["port"],
                        adminKey: row["admin_key"],
                        autoStart: (row["auto_start"] as Int) != 0
                    )
                }
        } ?? nil
    }

    private static func migrateFromJSON() -> Row? {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoderSwitch", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("proxy.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let stored = try? JSONDecoder().decode(LegacyStored.self, from: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: jsonURL)
        return Row(port: stored.port, adminKey: stored.adminKey, autoStart: stored.autoStart)
    }

    private struct LegacyStored: Codable {
        let port: Int
        let adminKey: String
        let autoStart: Bool
    }

    private func save() {
        let port = self.port
        let adminKey = self.adminKey
        let autoStart = self.autoStart
        try? db.write { db in
            try db.execute(
                sql: """
                INSERT INTO proxy_settings (id, port, admin_key, auto_start)
                VALUES (1, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    port = excluded.port,
                    admin_key = excluded.admin_key,
                    auto_start = excluded.auto_start
                """,
                arguments: [port, adminKey, autoStart ? 1 : 0]
            )
        }
    }
}
