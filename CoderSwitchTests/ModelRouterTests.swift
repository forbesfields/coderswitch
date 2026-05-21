import XCTest
@testable import CoderSwitch

final class ModelRouterTests: XCTestCase {
    func testRoutesProviderAndLabelPrefix() {
        let account = Account(label: "Work", provider: .openRouter)
        let router = ModelRouter(accounts: [account])

        let resolved = router.resolve(
            model: "openrouter:work/anthropic/claude-3.5-sonnet",
            compatibility: .openAI
        )

        XCTAssertEqual(resolved?.account.id, account.id)
        XCTAssertEqual(resolved?.upstreamModel, "anthropic/claude-3.5-sonnet")
    }

    func testPreferredAccountOverridesUnprefixedModel() {
        let first = Account(label: "Default", provider: .openAICompatible, customEndpoint: "https://one.example/v1")
        let second = Account(label: "Preferred", provider: .openAICompatible, customEndpoint: "https://two.example/v1")
        let router = ModelRouter(accounts: [first, second])

        let resolved = router.resolve(
            model: "gpt-5-mini",
            compatibility: .openAI,
            preferredAccountID: second.id
        )

        XCTAssertEqual(resolved?.account.id, second.id)
        XCTAssertEqual(resolved?.upstreamModel, "gpt-5-mini")
    }

    func testPreferredAnthropicAccountAliasUsesDefaultModel() {
        var first = Account(label: "Default", provider: .anthropicCompatible, customEndpoint: "https://one.example")
        first.defaultModel = "claude-3-5-haiku"
        var second = Account(label: "Work", provider: .anthropicCompatible, customEndpoint: "https://two.example")
        second.defaultModel = "claude-3-5-sonnet"
        let router = ModelRouter(accounts: [first, second])

        let resolved = router.resolve(
            model: "anthropic:work",
            compatibility: .anthropic,
            preferredAccountID: second.id
        )

        XCTAssertEqual(resolved?.account.id, second.id)
        XCTAssertEqual(resolved?.upstreamModel, "claude-3-5-sonnet")
    }

    func testDisabledAccountsAreSkipped() {
        var disabled = Account(label: "Disabled", provider: .openAICompatible, customEndpoint: "https://off.example/v1")
        disabled.isEnabled = false
        let enabled = Account(label: "Enabled", provider: .openAICompatible, customEndpoint: "https://on.example/v1")
        let router = ModelRouter(accounts: [disabled, enabled])

        let resolved = router.resolve(model: "gpt-5-mini", compatibility: .openAI)

        XCTAssertEqual(resolved?.account.id, enabled.id)
    }

    func testPreferredDisabledAccountDoesNotRoute() {
        var account = Account(label: "Disabled", provider: .openAICompatible, customEndpoint: "https://off.example/v1")
        account.isEnabled = false
        let router = ModelRouter(accounts: [account])

        let resolved = router.resolve(
            model: "gpt-5-mini",
            compatibility: .openAI,
            preferredAccountID: account.id
        )

        XCTAssertNil(resolved)
    }

    func testLegacyProxyProviderAccountDecodesAsCustomOpenAIEndpoint() throws {
        XCTAssertFalse(Provider.allCases.contains { $0.rawValue == "ikunCode" })
        XCTAssertFalse(Provider.allCases.contains { $0.rawValue == "fishXCode" })

        let account = Account(label: "Legacy", provider: .openRouter)
        let encoder = JSONEncoder()
        let data = try encoder.encode(account)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let legacyJson = json.replacingOccurrences(of: "\"provider\":\"openRouter\"", with: "\"provider\":\"ikunCode\"")

        let decoded = try JSONDecoder().decode(Account.self, from: XCTUnwrap(legacyJson.data(using: .utf8)))

        XCTAssertEqual(decoded.provider, .openAICompatible)
        XCTAssertEqual(decoded.customEndpoint, "https://api.ikuncode.cc/v1")
    }
}
