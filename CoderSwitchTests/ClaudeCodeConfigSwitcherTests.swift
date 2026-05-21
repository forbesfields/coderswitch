import XCTest
@testable import CoderSwitch

final class ClaudeCodeConfigSwitcherTests: XCTestCase {
    func testSwitchToCoderSwitchPreservesUnrelatedSettingsAndWritesClaudeEnv() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeConfigSwitcherTests-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        {
          "permissions": { "allow": ["Bash(ls)"] },
          "env": {
            "KEEP_ME": "yes",
            "ANTHROPIC_API_KEY": "old",
            "ANTHROPIC_MODEL": "old-model"
          }
        }
        """.utf8).write(to: settingsURL)

        let account = Account(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            label: "Work",
            provider: .anthropicCompatible,
            customEndpoint: "https://upstream.example",
            defaultModel: "claude-work"
        )
        try ClaudeCodeConfigSwitcher(settingsURL: settingsURL).switchToCoderSwitch(
            account: account,
            proxyBaseURL: "http://localhost:8484/",
            adminKey: "cs-test"
        )

        let settings = try readSettings(settingsURL)
        let env = try XCTUnwrap(settings["env"] as? [String: Any])
        XCTAssertNotNil(settings["permissions"])
        XCTAssertEqual(env["KEEP_ME"] as? String, "yes")
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertEqual(env["ANTHROPIC_MODEL"] as? String, "claude-work")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"] as? String, "http://localhost:8484")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"] as? String, "cs-test:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String, "claude-work")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.appendingPathExtension("coderswitch.bak").path))
    }

    func testSwitchToCoderSwitchRemovesStaleManagedModelDefaultsWhenAccountHasNoDefaultModel() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeConfigSwitcherTests-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        {
          "env": {
            "ANTHROPIC_MODEL": "old-model",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "old-model",
            "KEEP_ME": "yes"
          }
        }
        """.utf8).write(to: settingsURL)

        let account = Account(label: "Work", provider: .anthropicCompatible, customEndpoint: "https://upstream.example")
        try ClaudeCodeConfigSwitcher(settingsURL: settingsURL).switchToCoderSwitch(
            account: account,
            proxyBaseURL: "http://localhost:8484",
            adminKey: "cs-test"
        )

        let settings = try readSettings(settingsURL)
        let env = try XCTUnwrap(settings["env"] as? [String: Any])
        XCTAssertNil(env["ANTHROPIC_MODEL"])
        XCTAssertNil(env["ANTHROPIC_DEFAULT_SONNET_MODEL"])
        XCTAssertEqual(env["KEEP_ME"] as? String, "yes")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"] as? String, "http://localhost:8484")
    }

    func testRestoreOfficialClaudeRemovesOnlyManagedEnvKeys() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeConfigSwitcherTests-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        {
          "env": {
            "KEEP_ME": "yes",
            "ANTHROPIC_BASE_URL": "http://localhost:8484",
            "ANTHROPIC_AUTH_TOKEN": "cs-test:account",
            "ANTHROPIC_MODEL": "old-model"
          }
        }
        """.utf8).write(to: settingsURL)

        try ClaudeCodeConfigSwitcher(settingsURL: settingsURL).restoreOfficialClaude()

        let settings = try readSettings(settingsURL)
        let env = try XCTUnwrap(settings["env"] as? [String: Any])
        XCTAssertEqual(env.count, 1)
        XCTAssertEqual(env["KEEP_ME"] as? String, "yes")
    }

    func testClaudeCodeDefaultModelPrefersConfiguredDefault() {
        let account = Account(
            label: "custom anthropic",
            provider: .anthropicCompatible,
            customEndpoint: "https://api.example.com",
            defaultModel: "claude-sonnet-4"
        )

        XCTAssertEqual(account.claudeCodeDefaultModel, "claude-sonnet-4")
    }

    private func readSettings(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
