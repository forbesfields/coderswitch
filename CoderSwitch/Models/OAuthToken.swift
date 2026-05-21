import Foundation

struct OAuthToken: Codable, Sendable, Equatable, Hashable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scope: String?
    let idToken: String?

    init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.idToken = idToken
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    var isNearExpiry: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(60 * 5) >= expiresAt
    }
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case idToken = "id_token"
    }

    func toOAuthToken(fallbackRefreshToken: String? = nil, fallbackIDToken: String? = nil) -> OAuthToken {
        OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken ?? fallbackRefreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            scope: scope,
            idToken: idToken ?? fallbackIDToken
        )
    }
}
