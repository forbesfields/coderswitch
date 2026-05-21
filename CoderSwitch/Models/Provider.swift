import Foundation

enum APICompatibility: String, Codable, Hashable, Sendable {
    case openAI
    case anthropic
}

enum Provider: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case codex
    case openAI
    case anthropic
    case openRouter
    case miniMax
    case ikunCode
    case fishXCode
    case openAICompatible
    case anthropicCompatible
    case googleAntigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        case .miniMax: "MiniMax"
        case .ikunCode: "ikuncode.cc"
        case .fishXCode: "fishxcode.com"
        case .openAICompatible: "OpenAI-compatible (custom)"
        case .anthropicCompatible: "Anthropic-compatible (custom)"
        case .googleAntigravity: "Google Antigravity"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .codex: "https://chatgpt.com/backend-api"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .miniMax: "https://api.minimax.io/v1"
        case .ikunCode: "https://api.ikuncode.cc/v1"
        case .fishXCode: "https://api.fishxcode.com/v1"
        case .googleAntigravity: "https://generativelanguage.googleapis.com/v1beta"
        case .openAICompatible, .anthropicCompatible: ""
        }
    }

    var requiresCustomEndpoint: Bool {
        switch self {
        case .openAICompatible, .anthropicCompatible: true
        default: false
        }
    }

    var compatibility: APICompatibility {
        switch self {
        case .codex, .openAI, .openRouter, .miniMax, .ikunCode, .fishXCode, .openAICompatible, .googleAntigravity: .openAI
        case .anthropic, .anthropicCompatible: .anthropic
        }
    }

    var canAddWithAPIKey: Bool {
        self != .codex && self != .googleAntigravity
    }

    var isProxyRoutable: Bool {
        self != .codex && self != .googleAntigravity
    }

    var isClaudeCodeCompatible: Bool {
        isProxyRoutable && compatibility == .anthropic
    }
}
