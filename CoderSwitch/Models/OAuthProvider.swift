import Foundation

enum OAuthProvider: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .gemini: return "Google Antigravity"
        }
    }

    var iconName: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "sparkles"
        }
    }

    var authURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://auth.openai.com/oauth/authorize")!
        case .gemini:
            return URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        }
    }

    var tokenURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://auth.openai.com/oauth/token")!
        case .gemini:
            return URL(string: "https://oauth2.googleapis.com/token")!
        }
    }

    var userInfoURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://api.openai.com/v1/profile")!
        case .gemini:
            return URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        }
    }

    var scopes: String {
        switch self {
        case .codex:
            return "openid email profile offline_access"
        case .gemini:
            return "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
        }
    }

    var callbackPath: String {
        switch self {
        case .codex: return "/auth/callback"
        case .gemini: return "/oauth2callback"
        }
    }

    var callbackPort: UInt16 {
        switch self {
        case .codex: return 1455
        case .gemini: return 8085
        }
    }

    var clientID: String {
        switch self {
        case .codex:
            return "app_EMoamEEZ73f0CkXaXp7hrann"
        case .gemini:
            return "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
        }
    }

    var clientSecret: String? {
        switch self {
        case .codex:
            return nil
        case .gemini:
            return Self.configuredSecret(
                environmentKey: "CODERSWITCH_GOOGLE_OAUTH_CLIENT_SECRET",
                infoDictionaryKey: "CoderSwitchGoogleOAuthClientSecret"
            )
        }
    }

    var originator: String {
        switch self {
        case .codex:
            return "codex_chatgpt_desktop"
        case .gemini:
            return ""
        }
    }

    var requiresClientSecret: Bool {
        clientSecret != nil
    }
}

private extension OAuthProvider {
    static func configuredSecret(environmentKey: String, infoDictionaryKey: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environmentKey]?.trimmedNonEmptySecret {
            return value
        }

        return (Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String)?.trimmedNonEmptySecret
    }
}

private extension String {
    var trimmedNonEmptySecret: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }
}
