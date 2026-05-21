import Foundation

enum OAuthAccountAuthSource: String, Codable, Hashable, Sendable {
    case oauth
    case json

    var displayName: String { rawValue.uppercased() }
}

struct OAuthAccount: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var label: String
    var provider: OAuthProvider
    var email: String?
    var externalID: String?
    let createdAt: Date
    var token: OAuthToken
    var authSource: OAuthAccountAuthSource
    var lastCheckedAt: Date?
    var lastCheckError: String?

    init(
        id: UUID = UUID(),
        label: String,
        provider: OAuthProvider,
        email: String? = nil,
        externalID: String? = nil,
        token: OAuthToken,
        createdAt: Date = Date(),
        authSource: OAuthAccountAuthSource = .oauth,
        lastCheckedAt: Date? = nil,
        lastCheckError: String? = nil
    ) {
        self.id = id
        self.label = label
        self.provider = provider
        self.email = email
        self.externalID = externalID
        self.token = token
        self.createdAt = createdAt
        self.authSource = authSource
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckError = lastCheckError
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case provider
        case email
        case externalID
        case createdAt
        case token
        case authSource
        case lastCheckedAt
        case lastCheckError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        provider = try container.decode(OAuthProvider.self, forKey: .provider)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        token = try container.decode(OAuthToken.self, forKey: .token)
        authSource = try container.decodeIfPresent(OAuthAccountAuthSource.self, forKey: .authSource) ?? .oauth
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastCheckError = try container.decodeIfPresent(String.self, forKey: .lastCheckError)
    }
}
