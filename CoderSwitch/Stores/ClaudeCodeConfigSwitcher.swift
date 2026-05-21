import Foundation

struct ClaudeCodeConfigSwitcher {
    let settingsURL: URL
    let fileManager: FileManager

    init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json"),
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL
        self.fileManager = fileManager
    }

    func switchToCoderSwitch(
        account: Account,
        proxyBaseURL: String,
        adminKey: String
    ) throws {
        let token = "\(adminKey):\(account.id.uuidString)"
        var env: [String: String] = [
            "ANTHROPIC_BASE_URL": proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "ANTHROPIC_AUTH_TOKEN": token,
            "API_TIMEOUT_MS": "600000",
        ]
        if let defaultModel = account.claudeCodeDefaultModel {
            env["ANTHROPIC_MODEL"] = defaultModel
            env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = defaultModel
            env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = defaultModel
            env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = defaultModel
        }
        try updateSettings { settings in
            var currentEnv = settings["env"] as? [String: Any] ?? [:]
            for key in Self.managedEnvKeys {
                currentEnv.removeValue(forKey: key)
            }
            for (key, value) in env {
                currentEnv[key] = value
            }
            settings["env"] = currentEnv
        }
    }

    func restoreOfficialClaude() throws {
        try updateSettings { settings in
            guard var env = settings["env"] as? [String: Any] else { return }
            for key in Self.managedEnvKeys {
                env.removeValue(forKey: key)
            }
            if env.isEmpty {
                settings.removeValue(forKey: "env")
            } else {
                settings["env"] = env
            }
        }
    }

    private func updateSettings(_ update: (inout [String: Any]) -> Void) throws {
        var settings = try readSettings()
        update(&settings)
        try writeSettings(settings)
    }

    private func readSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any] ?? [:]
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let dir = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let finalData = data + Data("\n".utf8)
        let tmpURL = dir.appendingPathComponent(".\(settingsURL.lastPathComponent).tmp.\(UUID().uuidString)")
        try finalData.write(to: tmpURL, options: .atomic)
        _ = try? fileManager.removeItem(at: settingsURL.appendingPathExtension("coderswitch.bak"))
        if fileManager.fileExists(atPath: settingsURL.path) {
            try? fileManager.copyItem(
                at: settingsURL,
                to: settingsURL.appendingPathExtension("coderswitch.bak")
            )
        }
        _ = try fileManager.replaceItemAt(settingsURL, withItemAt: tmpURL)
    }

    private static let managedEnvKeys: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "API_TIMEOUT_MS",
    ]
}

extension Account {
    var claudeCodeDefaultModel: String? {
        if let defaultModel = defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultModel.isEmpty {
            return defaultModel
        }
        return availableModels?.first?.id.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
