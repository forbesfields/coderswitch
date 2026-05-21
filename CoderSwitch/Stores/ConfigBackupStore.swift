import Foundation

struct CoderSwitchConfigArchive: Codable {
    let format: String
    let version: Int
    let exportedAt: Date
    let proxySettings: CoderSwitchConfigProxySettings
    let accounts: [CoderSwitchConfigAccount]
    let oauthAccounts: [OAuthAccount]

    init(
        exportedAt: Date = Date(),
        proxySettings: CoderSwitchConfigProxySettings,
        accounts: [CoderSwitchConfigAccount],
        oauthAccounts: [OAuthAccount]
    ) {
        self.format = "dev.forbes.CoderSwitch.config"
        self.version = 1
        self.exportedAt = exportedAt
        self.proxySettings = proxySettings
        self.accounts = accounts
        self.oauthAccounts = oauthAccounts
    }
}

struct CoderSwitchConfigProxySettings: Codable, Equatable {
    let port: Int
    let adminKey: String
    let autoStart: Bool
}

struct CoderSwitchConfigAccount: Codable {
    let account: Account
    let apiKey: String?
}

enum ConfigBackupError: LocalizedError {
    case unsupportedFormat
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "That file does not look like a CoderSwitch config backup."
        case .unsupportedVersion(let version):
            return "CoderSwitch config backup version \(version) is not supported."
        }
    }
}

@MainActor
enum ConfigBackupStore {
    static func exportArchive(
        accountStore: AccountStore,
        oauthStore: OAuthStore,
        proxySettings: ProxySettings
    ) -> CoderSwitchConfigArchive {
        CoderSwitchConfigArchive(
            proxySettings: proxySettings.configExportItem,
            accounts: accountStore.configExportItems(),
            oauthAccounts: oauthStore.configExportItems()
        )
    }

    static func write(
        archive: CoderSwitchConfigArchive,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> CoderSwitchConfigArchive {
        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(CoderSwitchConfigArchive.self, from: data)
        guard archive.format == "dev.forbes.CoderSwitch.config" else {
            throw ConfigBackupError.unsupportedFormat
        }
        guard archive.version == 1 else {
            throw ConfigBackupError.unsupportedVersion(archive.version)
        }
        return archive
    }

    static func importArchive(
        _ archive: CoderSwitchConfigArchive,
        accountStore: AccountStore,
        oauthStore: OAuthStore,
        proxySettings: ProxySettings
    ) throws {
        try oauthStore.replaceAll(with: archive.oauthAccounts)
        try accountStore.replaceAll(with: archive.accounts)
        proxySettings.applyConfigImport(archive.proxySettings)
    }

    static func deleteAllUserData(
        accountStore: AccountStore,
        oauthStore: OAuthStore,
        proxySettings: ProxySettings,
        requestLogStore: RequestLogStore
    ) throws {
        try oauthStore.replaceAll(with: [])
        try accountStore.replaceAll(with: [])
        requestLogStore.clear()
        proxySettings.resetToDefaults()
    }
}
