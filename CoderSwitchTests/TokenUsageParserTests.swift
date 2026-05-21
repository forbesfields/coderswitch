import XCTest
@testable import CoderSwitch

final class TokenUsageParserTests: XCTestCase {
    func testParsesResponsesUsageObject() throws {
        let data = Data("""
        {
          "usage": {
            "input_tokens": 12,
            "output_tokens": 7,
            "total_tokens": 21,
            "input_tokens_details": {
              "cached_tokens": 3
            }
          }
        }
        """.utf8)

        let usage = try XCTUnwrap(TokenUsageParser.parseJSONResponse(data))

        XCTAssertEqual(usage.inputTokens, 12)
        XCTAssertEqual(usage.outputTokens, 7)
        XCTAssertEqual(usage.cacheReadTokens, 3)
        XCTAssertEqual(usage.uncategorizedTokens, 2)
    }

    func testParsesResponsesStreamingCompletedEvent() throws {
        let event = """
        event: response.completed
        data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":4,"total_tokens":14}}}

        """

        let usage = try XCTUnwrap(TokenUsageParser.parseSSEEvent(event))

        XCTAssertEqual(usage.inputTokens, 10)
        XCTAssertEqual(usage.outputTokens, 4)
        XCTAssertEqual(usage.totalTokens, 14)
    }

    func testParsesAnthropicMessageUsageEnvelope() throws {
        let data = Data("""
        {
          "message": {
            "usage": {
              "input_tokens": 8,
              "output_tokens": 5,
              "cache_creation_input_tokens": 2,
              "cache_read_input_tokens": 1
            }
          }
        }
        """.utf8)

        let usage = try XCTUnwrap(TokenUsageParser.parseJSONResponse(data))

        XCTAssertEqual(usage.inputTokens, 8)
        XCTAssertEqual(usage.outputTokens, 5)
        XCTAssertEqual(usage.cacheWriteTokens, 2)
        XCTAssertEqual(usage.cacheReadTokens, 1)
    }
}
