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
}
