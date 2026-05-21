import XCTest
@testable import CoderSwitch

final class QuotaCheckTests: XCTestCase {
    func testOpenRouterCreditsParseAsPayAsYouGoBalance() throws {
        let data = Data("""
        {
          "data": {
            "total_credits": 20.0,
            "total_usage": 7.5
          }
        }
        """.utf8)

        let check = try XCTUnwrap(Provider.openRouter.quotaCheck)
        let limits = try check.parse(data, 200)

        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].name, "Balance")
        XCTAssertEqual(limits[0].used, 12.5)
        XCTAssertTrue(limits[0].isPayAsYouGo)
    }

    func testMiniMaxRemainsParsesRemainingRequestWindows() throws {
        let data = Data("""
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "ok"
          },
          "model_remains": [
            {
              "model_name": "MiniMax-M2.7",
              "current_interval_total_count": 100,
              "current_interval_remaining_count": 25,
              "weekly_total_count": 500,
              "weekly_remaining_count": 200
            }
          ]
        }
        """.utf8)

        let check = try XCTUnwrap(Provider.miniMax.quotaCheck)
        let limits = try check.parse(data, 200)

        XCTAssertEqual(limits.map(\.name), ["MiniMax-M2.7", "MiniMax-M2.7 weekly"])
        XCTAssertEqual(limits[0].used, 75)
        XCTAssertEqual(limits[0].limit, 100)
        XCTAssertEqual(limits[1].used, 300)
        XCTAssertEqual(limits[1].limit, 500)
    }

    func testMiniMaxUsageCountIsRemainingRequests() throws {
        let data = Data("""
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "ok"
          },
          "model_remains": [
            {
              "model_name": "MiniMax-M2.7",
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 22
            }
          ]
        }
        """.utf8)

        let check = try XCTUnwrap(Provider.miniMax.quotaCheck)
        let limits = try check.parse(data, 200)

        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].used, 22)
        XCTAssertEqual(limits[0].limit, 1500)
        XCTAssertEqual(limits[0].fraction, 22.0 / 1500.0)
        XCTAssertEqual(limits[0].valueKind, "minimaxRemainingNormalized")
    }

    func testMiniMaxUsageCountTakesPriorityWhenOtherCountFieldsDisagree() throws {
        let data = Data("""
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "ok"
          },
          "model_remains": [
            {
              "model_name": "MiniMax-M*",
              "current_interval_total_count": 1500,
              "current_interval_remaining_count": 999,
              "current_interval_usage_count": 22
            }
          ]
        }
        """.utf8)

        let check = try XCTUnwrap(Provider.miniMax.quotaCheck)
        let limits = try check.parse(data, 200)

        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].used, 22)
        XCTAssertEqual(limits[0].limit, 1500)
        XCTAssertEqual(limits[0].fraction, 22.0 / 1500.0)
    }

    func testLegacyMiniMaxStoredRemainingCountMigratesToUsedCount() throws {
        let data = Data("""
        {
          "createdAt": 800946669.87835,
          "id": "176D8D27-7C20-4682-A6C8-84D6F25729B7",
          "isEnabled": true,
          "label": "minimax",
          "provider": "miniMax",
          "usageLimits": [
            {
              "isPayAsYouGo": false,
              "limit": 1500,
              "name": "MiniMax-M*",
              "unit": " requests",
              "used": 1478
            }
          ]
        }
        """.utf8)

        let account = try JSONDecoder().decode(Account.self, from: data)

        XCTAssertEqual(account.usageLimits.count, 1)
        XCTAssertEqual(account.usageLimits[0].used, 22)
        XCTAssertEqual(account.usageLimits[0].limit, 1500)
        XCTAssertEqual(account.usageLimits[0].fraction, 22.0 / 1500.0)
        XCTAssertEqual(account.usageLimits[0].valueKind, "minimaxRemainingNormalized")
    }

    func testMarkedLegacyMiniMaxRemainingCountMigratesToUsedCount() throws {
        let data = Data("""
        {
          "createdAt": 800946669.87835,
          "id": "176D8D27-7C20-4682-A6C8-84D6F25729B7",
          "isEnabled": true,
          "label": "minimax",
          "provider": "miniMax",
          "usageLimits": [
            {
              "isPayAsYouGo": false,
              "limit": 1500,
              "name": "MiniMax-M*",
              "unit": " requests",
              "used": 1478,
              "valueKind": "used"
            }
          ]
        }
        """.utf8)

        let account = try JSONDecoder().decode(Account.self, from: data)

        XCTAssertEqual(account.usageLimits.count, 1)
        XCTAssertEqual(account.usageLimits[0].used, 22)
        XCTAssertEqual(account.usageLimits[0].limit, 1500)
        XCTAssertEqual(account.usageLimits[0].fraction, 22.0 / 1500.0)
        XCTAssertEqual(account.usageLimits[0].valueKind, "minimaxRemainingNormalized")
    }

    func testMarkedMiniMaxUsedCountDoesNotMigrateAgain() throws {
        let data = Data("""
        {
          "createdAt": 800946669.87835,
          "id": "176D8D27-7C20-4682-A6C8-84D6F25729B7",
          "isEnabled": true,
          "label": "minimax",
          "provider": "miniMax",
          "usageLimits": [
            {
              "isPayAsYouGo": false,
              "limit": 1500,
              "name": "MiniMax-M*",
              "unit": " requests",
              "used": 22,
              "valueKind": "minimaxRemainingNormalized"
            }
          ]
        }
        """.utf8)

        let account = try JSONDecoder().decode(Account.self, from: data)

        XCTAssertEqual(account.usageLimits.count, 1)
        XCTAssertEqual(account.usageLimits[0].used, 22)
        XCTAssertEqual(account.usageLimits[0].limit, 1500)
        XCTAssertEqual(account.usageLimits[0].fraction, 22.0 / 1500.0)
    }

    func testGoogleAntigravityRemainingZeroShowsFullUsageBar() throws {
        let limit = UsageLimit(
            name: "Gemini",
            used: 0,
            limit: 100,
            unit: "%",
            valueKind: "googleAntigravityRemainingPercent"
        )

        XCTAssertEqual(limit.fraction, 1)
        XCTAssertEqual(limit.remainingDescription, "100% used")
    }

    func testGoogleAntigravityRemainingPercentInvertsToConsumedFraction() throws {
        let limit = UsageLimit(
            name: "Gemini",
            used: 35,
            limit: 100,
            unit: "%",
            valueKind: "googleAntigravityRemainingPercent"
        )

        XCTAssertEqual(limit.fraction, 0.65)
        XCTAssertEqual(limit.remainingDescription, "65% used")
    }

    func testGoogleAntigravityFiltersPlaceholderAndTabModels() throws {
        let data = Data("""
        {
          "models": {
            "tab_flash_lite_preview": {
              "displayName": "MODEL_PLACEHOLDER_M19",
              "quotaInfo": {
                "remainingFraction": 1.0
              }
            },
            "tab_jump_flash_lite_preview": {
              "displayName": "MODEL_PLACEHOLDER_M28",
              "quotaInfo": {
                "remainingFraction": 1.0
              }
            },
            "gemini-3-pro-high": {
              "displayName": "Gemini 3 Pro (High)",
              "quotaInfo": {
                "remainingFraction": 0.35
              }
            }
          }
        }
        """.utf8)

        let usage = try JSONDecoder().decode(AntigravityFetchAvailableModelsResponse.self, from: data)
        let limits = usage.usageLimits

        XCTAssertEqual(limits.map(\.name), ["Gemini 3 Pro (High)"])
        XCTAssertEqual(limits[0].storageID, "gemini-3-pro-high")
        XCTAssertEqual(limits[0].used, 35)
    }

    func testGoogleAntigravityKeepsModelIDWhenDisplayNameIsMissing() throws {
        let data = Data("""
        {
          "models": {
            "gemini-3-flash": {
              "quotaInfo": {
                "remainingFraction": 0.8
              }
            }
          }
        }
        """.utf8)

        let usage = try JSONDecoder().decode(AntigravityFetchAvailableModelsResponse.self, from: data)
        let limits = usage.usageLimits

        XCTAssertEqual(limits.map(\.name), ["gemini-3-flash"])
        XCTAssertEqual(limits[0].storageID, "gemini-3-flash")
    }

    func testCodexUsageAllowsObjectRateLimitReachedType() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit_reached_type": {
            "type": "rate_limit_reached",
            "details": "default"
          },
          "rate_limit": {
            "primary_window": {
              "used_percent": 100,
              "limit_window_seconds": 18000,
              "reset_at": 1779310701
            },
            "secondary_window": {
              "used_percent": 16,
              "limit_window_seconds": 604800,
              "reset_at": 1779897501
            }
          },
          "credits": {
            "has_credits": false,
            "unlimited": false,
            "balance": "0"
          }
        }
        """.utf8)

        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let limits = usage.usageLimits

        XCTAssertEqual(limits.map(\.name), ["5-hour limit", "Weekly limit"])
        XCTAssertEqual(limits[0].used, 100)
        XCTAssertEqual(limits[1].used, 16)
    }
}
