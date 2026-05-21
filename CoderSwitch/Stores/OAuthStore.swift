import Foundation
import Observation
import Network
import AppKit
import GRDB

@Observable
@MainActor
final class OAuthStore {
    static let shared = OAuthStore()

    private(set) var accounts: [OAuthAccount] = []
    private var pkceChallenge: PKCEChallenge?
    private var callbackListener: NWListener?
    private var pendingCompletion: ((Result<OAuthAccount, Error>) -> Void)?
    private var lastAuthURL: URL?

    private let db: DatabaseQueue

    private init() {
        self.db = AppDatabase.shared.queue
        load()
        migrateFromJSONIfNeeded()
        importCurrentCodexAuthIfNeeded()
        importCodexMultiAuthAccountsIfNeeded()
    }

    func accounts(for provider: OAuthProvider) -> [OAuthAccount] {
        accounts.filter { $0.provider == provider }
    }

    func codexAccount(matching account: Account) -> OAuthAccount? {
        accounts.first { oauth in
            oauth.provider == .codex
                && (
                    oauth.id == account.id
                    || (oauth.externalID != nil && oauth.externalID == account.externalID)
                    || (oauth.email != nil && oauth.email == account.label)
                )
        }
    }

    func geminiAccount(matching account: Account) -> OAuthAccount? {
        accounts.first { oauth in
            oauth.provider == .gemini
                && (
                    oauth.id == account.id
                    || (oauth.externalID != nil && oauth.externalID == account.externalID)
                    || (oauth.email != nil && oauth.email == account.label)
                )
        }
    }

    func add(_ account: OAuthAccount) {
        do {
            try persist(account)
            accounts.append(account)
        } catch {
            print("OAuthStore.add failed: \(error)")
        }
    }

    func configExportItems() -> [OAuthAccount] {
        accounts
    }

    func replaceAll(with importedAccounts: [OAuthAccount]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rows = try importedAccounts.map { account in
            var stripped = account
            stripped.token = OAuthToken(
                accessToken: "",
                refreshToken: nil,
                expiresAt: account.token.expiresAt,
                scope: account.token.scope,
                idToken: nil
            )
            let json = String(data: try encoder.encode(stripped), encoding: .utf8) ?? "{}"
            let accessBlob = try SecretBox.seal(account.token.accessToken)
            let refreshBlob: Data? = try account.token.refreshToken.map { try SecretBox.seal($0) }
            let idTokenBlob: Data? = try account.token.idToken.map { try SecretBox.seal($0) }
            return (
                id: account.id.uuidString,
                json: json,
                access: accessBlob,
                refresh: refreshBlob,
                idToken: idTokenBlob,
                createdAt: Int64(account.createdAt.timeIntervalSince1970)
            )
        }

        try db.write { db in
            try db.execute(sql: "DELETE FROM oauth_accounts")
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO oauth_accounts (id, json, access_token_encrypted, refresh_token_encrypted, id_token_encrypted, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [row.id, row.json, row.access, row.refresh, row.idToken, row.createdAt]
                )
            }
        }
        accounts = importedAccounts
    }

    @discardableResult
    func importCodexAuth(from url: URL) throws -> CodexAuthImportResult {
        try importCodexAuth(from: url, updateExistingSource: true)
    }

    @discardableResult
    private func importCodexAuth(from url: URL, updateExistingSource: Bool) throws -> CodexAuthImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let auth: CodexAuthFile
        do {
            auth = try decoder.decode(CodexAuthFile.self, from: data)
        } catch {
            throw OAuthError.invalidCodexAuthFile
        }
        guard auth.authMode == "chatgpt" else {
            throw OAuthError.unsupportedCodexAuthMode(auth.authMode)
        }
        return try importCodexAuth(auth, authSource: .json, updateExistingSource: updateExistingSource)
    }

    func delete(_ account: OAuthAccount) {
        let id = account.id.uuidString
        try? db.write { db in
            try db.execute(sql: "DELETE FROM oauth_accounts WHERE id = ?", arguments: [id])
        }
        deleteCLIProxyAuth(account: account)
        accounts.removeAll { $0.id == account.id }
    }

    func updateToken(for accountID: UUID, token: OAuthToken) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].token = OAuthToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? accounts[idx].token.refreshToken,
            expiresAt: token.expiresAt,
            scope: token.scope,
            idToken: token.idToken ?? accounts[idx].token.idToken
        )
        try? persist(accounts[idx])
    }

    func startOAuthFlow(provider: OAuthProvider) async throws -> URL? {
        pkceChallenge = PKCEChallenge()

        try await startCallbackServer(for: provider)

        var components = URLComponents(url: provider.authURL, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: provider.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(for: provider)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: provider.scopes),
            URLQueryItem(name: "code_challenge", value: pkceChallenge?.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        if provider == .codex {
            queryItems.append(URLQueryItem(name: "originator", value: provider.originator))
            queryItems.append(URLQueryItem(name: "codex_cli_simplified_flow", value: "true"))
            queryItems.append(URLQueryItem(name: "id_token_add_organizations", value: "true"))
            queryItems.append(URLQueryItem(name: "prompt", value: "login"))
        } else if provider == .gemini {
            queryItems.append(URLQueryItem(name: "access_type", value: "offline"))
            queryItems.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        components.queryItems = queryItems
        return components.url
    }

    func initiateOAuthFlow(provider: OAuthProvider, completion: @escaping (Result<OAuthAccount, Error>) -> Void) async throws {
        let authURL = try await startOAuthFlow(provider: provider)
        pendingCompletion = completion
        lastAuthURL = authURL
        if let authURL { NSWorkspace.shared.open(authURL) }
    }

    func currentAuthURL(for provider: OAuthProvider) async throws -> URL? {
        lastAuthURL
    }

    func cancelOAuthFlow() {
        stopCallbackServer()
        pkceChallenge = nil
        lastAuthURL = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(.failure(OAuthError.cancelled))
    }

    var hasPendingFlow: Bool {
        pendingCompletion != nil || callbackListener != nil
    }

    func handleAuthCallback(
        provider: OAuthProvider,
        code: String,
        completion: @escaping (Result<OAuthAccount, Error>) -> Void
    ) {
        pendingCompletion = completion
        completeAuthCallback(provider: provider, code: code)
    }

    private func completeAuthCallback(provider: OAuthProvider, code: String) {
        guard let challenge = pkceChallenge else {
            finishPending(.failure(OAuthError.missingPKCEChallenge))
            return
        }

        pkceChallenge = nil

        Task {
            do {
                let tokenResponse = try await exchangeCode(
                    provider: provider,
                    code: code,
                    verifier: challenge.verifier
                )
                let account = try await createAccount(
                    provider: provider,
                    token: tokenResponse.toOAuthToken()
                )
                try persist(account)
                accounts.append(account)
                try exportToCLIProxyAPI(account: account)
                stopCallbackServer()
                finishPending(.success(account))
            } catch {
                stopCallbackServer()
                finishPending(.failure(error))
            }
        }
    }

    private func finishPending(_ result: Result<OAuthAccount, Error>) {
        let completion = pendingCompletion
        pendingCompletion = nil
        lastAuthURL = nil
        completion?(result)
    }

    func refreshTokenIfNeeded(for account: OAuthAccount) async throws -> OAuthToken {
        let shouldRefresh = account.token.isNearExpiry || (account.provider == .codex && account.token.idToken == nil)
        guard shouldRefresh, let refreshToken = account.token.refreshToken else {
            return account.token
        }

        let provider = account.provider
        var request = URLRequest(url: provider.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "client_id": provider.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]

        if let clientSecret = provider.clientSecret {
            body["client_secret"] = clientSecret
        }

        request.httpBody = URLSession.urlEncodedForm(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        let newToken = tokenResponse.toOAuthToken(
            fallbackRefreshToken: account.token.refreshToken,
            fallbackIDToken: account.token.idToken
        )
        updateToken(for: account.id, token: newToken)
        return newToken
    }

    func switchToAccount(_ account: OAuthAccount) async throws {
        let token = try await refreshTokenIfNeeded(for: account)
        var refreshed = account
        refreshed.token = token
        switch account.provider {
        case .codex:
            try exportCodexAuthJSON(account: refreshed)
            try exportCodexCLIProxyAuth(account: refreshed)
        case .gemini:
            try exportGeminiCLIProxyAuth(account: refreshed)
        }
    }

    private func startCallbackServer(for provider: OAuthProvider) async throws {
        stopCallbackServer()

        let port = NWEndpoint.Port(integerLiteral: provider.callbackPort)

        callbackListener = try NWListener(using: .tcp, on: port)
        callbackListener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("OAuth callback server ready on port \(provider.callbackPort)")
            case .failed(let error):
                print("OAuth callback server failed: \(error)")
            default:
                break
            }
        }

        let providerCopy = provider
        callbackListener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleCallbackConnection(connection, provider: providerCopy)
            }
        }

        callbackListener?.start(queue: .main)
    }

    private func handleCallbackConnection(_ connection: NWConnection, provider: OAuthProvider) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) }
            Task { @MainActor in
                guard let self,
                      let request,
                      !request.isEmpty else {
                    connection.cancel()
                    return
                }

                if let url = self.extractCallbackURL(from: request, provider: provider) {
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
                    let errorParam = components?.queryItems?.first(where: { $0.name == "error" })?.value

                    if let error = errorParam {
                        print("OAuth error: \(error)")
                        self.finishPending(.failure(OAuthError.providerError(error)))
                        self.stopCallbackServer()
                        self.pkceChallenge = nil
                    } else if let code = code {
                        self.completeAuthCallback(provider: provider, code: code)
                    }
                }

                let redirectHTML = """
                <!DOCTYPE html>
                <html>
                <head><title>Authenticated</title></head>
                <body>
                <p>Authentication successful! You can close this window.</p>
                <script>
                    setTimeout(function() { window.close(); }, 1000);
                </script>
                </body>
                </html>
                """

                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(redirectHTML.count)\r\n\r\n\(redirectHTML)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func extractCallbackURL(from request: String, provider: OAuthProvider) -> URL? {
        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            if line.hasPrefix("GET ") {
                let parts = line.split(separator: " ", maxSplits: 2)
                if parts.count >= 2 {
                    let path = String(parts[1])
                    return URL(string: "coderswitch://localhost\(path)")
                }
            }
        }
        return nil
    }

    private func stopCallbackServer() {
        callbackListener?.cancel()
        callbackListener = nil
    }

    private func exportToCLIProxyAPI(account: OAuthAccount) throws {
        switch account.provider {
        case .codex:
            try exportCodexCLIProxyAuth(account: account)
        case .gemini:
            try exportGeminiCLIProxyAuth(account: account)
        }
    }

    private func deleteCLIProxyAuth(account: OAuthAccount) {
        let filename: String
        switch account.provider {
        case .codex:
            filename = cliProxyCodexFilename(for: account)
        case .gemini:
            filename = cliProxyGeminiFilename(for: account)
        }
        try? FileManager.default.removeItem(at: cliProxyAuthDir().appendingPathComponent(filename))
    }

    private func exportCodexAuthJSON(account: OAuthAccount) throws {
        let token = account.token
        guard let idToken = token.idToken else {
            throw OAuthError.missingIDToken
        }

        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let authFile = configDir.appendingPathComponent("auth.json")

        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let claims = CodexAuthClaims.fromIDToken(idToken)
        let auth = CodexAuthFile(
            authMode: "chatgpt",
            openAIAPIKey: nil,
            tokens: CodexAuthTokens(
                idToken: idToken,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                accountID: account.externalID ?? claims?.accountID
            ),
            lastRefresh: ISO8601DateFormatter().string(from: Date()),
            email: account.email ?? claims?.email,
            codexMultiAuthSyncVersion: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try writeConfigFile(data, to: authFile)
    }

    private func exportCodexCLIProxyAuth(account: OAuthAccount) throws {
        let token = account.token
        guard let idToken = token.idToken else {
            throw OAuthError.missingIDToken
        }

        let configDir = cliProxyAuthDir()
        let authFile = configDir.appendingPathComponent(cliProxyCodexFilename(for: account))

        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let claims = CodexAuthClaims.fromIDToken(idToken)
        let auth = CLIProxyCodexAuthFile(
            idToken: idToken,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? "",
            accountID: account.externalID ?? claims?.accountID ?? "",
            lastRefresh: ISO8601DateFormatter().string(from: Date()),
            email: account.email ?? claims?.email,
            type: "codex",
            expired: cliProxyExpiryString(for: token, fallback: claims?.expiresAt)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try writeConfigFile(data, to: authFile)
    }

    private func exportGeminiCLIProxyAuth(account: OAuthAccount) throws {
        let token = account.token
        let configDir = cliProxyAuthDir()
        let authFile = configDir.appendingPathComponent(cliProxyGeminiFilename(for: account))

        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let auth = CLIProxyGeminiAuthFile(
            token: CLIProxyGeminiToken(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? "",
                tokenType: "Bearer",
                expiry: cliProxyExpiryString(for: token, fallback: nil),
                tokenURI: OAuthProvider.gemini.tokenURL.absoluteString,
                clientID: OAuthProvider.gemini.clientID,
                clientSecret: OAuthProvider.gemini.clientSecret ?? "",
                scopes: OAuthProvider.gemini.scopes.components(separatedBy: " "),
                universeDomain: "googleapis.com"
            ),
            projectID: "all",
            email: account.email ?? account.label,
            auto: true,
            checked: false,
            type: "gemini"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try writeConfigFile(data, to: authFile)
    }

    private func redirectURI(for provider: OAuthProvider) -> String {
        "http://localhost:\(provider.callbackPort)\(provider.callbackPath)"
    }

    private func exchangeCode(
        provider: OAuthProvider,
        code: String,
        verifier: String
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: provider.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "client_id": provider.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI(for: provider),
        ]

        if let clientSecret = provider.clientSecret {
            body["client_secret"] = clientSecret
        }

        request.httpBody = URLSession.urlEncodedForm(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func createAccount(
        provider: OAuthProvider,
        token: OAuthToken
    ) async throws -> OAuthAccount {
        let codexClaims = token.idToken.flatMap(CodexAuthClaims.fromIDToken)
        let fetchedEmail: String?
        if let email = codexClaims?.email {
            fetchedEmail = email
        } else {
            fetchedEmail = try await fetchEmail(for: provider, token: token)
        }
        let email = fetchedEmail
        let label = email ?? "\(provider.displayName) \(accounts.filter { $0.provider == provider }.count + 1)"
        return OAuthAccount(
            label: label,
            provider: provider,
            email: email,
            externalID: codexClaims?.accountID,
            token: token
        )
    }

    private func fetchEmail(for provider: OAuthProvider, token: OAuthToken) async throws -> String? {
        var request = URLRequest(url: provider.userInfoURL)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        struct UserInfo: Decodable { let email: String? }
        return try JSONDecoder().decode(UserInfo.self, from: data).email
    }

    private func persist(_ account: OAuthAccount) throws {
        var stripped = account
        stripped.token = OAuthToken(
            accessToken: "",
            refreshToken: nil,
            expiresAt: account.token.expiresAt,
            scope: account.token.scope,
            idToken: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(stripped), encoding: .utf8) ?? "{}"
        let accessBlob = try SecretBox.seal(account.token.accessToken)
        let refreshBlob: Data? = try account.token.refreshToken.map { try SecretBox.seal($0) }
        let idTokenBlob: Data? = try account.token.idToken.map { try SecretBox.seal($0) }
        let id = account.id.uuidString
        let createdAt = Int64(account.createdAt.timeIntervalSince1970)
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO oauth_accounts (id, json, access_token_encrypted, refresh_token_encrypted, id_token_encrypted, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    json = excluded.json,
                    access_token_encrypted = excluded.access_token_encrypted,
                    refresh_token_encrypted = excluded.refresh_token_encrypted,
                    id_token_encrypted = excluded.id_token_encrypted
                """,
                arguments: [id, json, accessBlob, refreshBlob, idTokenBlob, createdAt]
            )
        }
    }

    private func load() {
        struct LoadedRow {
            let json: Data
            let access: Data
            let refresh: Data?
            let idToken: Data?
        }
        let rows: [LoadedRow] = (try? db.read { db in
            try GRDB.Row.fetchAll(db, sql: """
                SELECT json, access_token_encrypted, refresh_token_encrypted, id_token_encrypted
                FROM oauth_accounts ORDER BY created_at ASC
                """).map { row in
                LoadedRow(
                    json: Data((row["json"] as String).utf8),
                    access: row["access_token_encrypted"],
                    refresh: row["refresh_token_encrypted"] as Data?,
                    idToken: row["id_token_encrypted"] as Data?
                )
            }
        }) ?? []
        let decoder = JSONDecoder()
        accounts = rows.compactMap { row in
            guard var account = try? decoder.decode(OAuthAccount.self, from: row.json),
                  let access = try? SecretBox.open(row.access) else { return nil }
            let refresh = row.refresh.flatMap { try? SecretBox.open($0) }
            let idToken = row.idToken.flatMap { try? SecretBox.open($0) }
            account.token = OAuthToken(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: account.token.expiresAt,
                scope: account.token.scope,
                idToken: idToken
            )
            return account
        }
    }

    private func migrateFromJSONIfNeeded() {
        guard accounts.isEmpty else { return }
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoderSwitch", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("oauth_accounts.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([OAuthAccount].self, from: data) else {
            return
        }
        for account in decoded {
            do {
                try persist(account)
                accounts.append(account)
            } catch {
                continue
            }
        }
        try? FileManager.default.removeItem(at: jsonURL)
    }

    private func importCurrentCodexAuthIfNeeded() {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")

        do {
            try importCodexAuth(from: authURL, updateExistingSource: false)
        } catch {
            return
        }
    }

    private func importCodexAuth(
        _ auth: CodexAuthFile,
        authSource: OAuthAccountAuthSource,
        updateExistingSource: Bool
    ) throws -> CodexAuthImportResult {
        let claims = CodexAuthClaims.fromIDToken(auth.tokens.idToken)
        let externalID = auth.tokens.accountID ?? claims?.accountID
        let email = auth.email ?? claims?.email
        let token = OAuthToken(
            accessToken: auth.tokens.accessToken,
            refreshToken: auth.tokens.refreshToken,
            expiresAt: claims?.expiresAt,
            scope: claims?.scope,
            idToken: auth.tokens.idToken
        )

        if let idx = accounts.firstIndex(where: { account in
            account.provider == .codex
                && (
                    (externalID != nil && account.externalID == externalID)
                    || (email != nil && account.email == email)
                )
        }) {
            accounts[idx].email = email ?? accounts[idx].email
            accounts[idx].externalID = externalID ?? accounts[idx].externalID
            accounts[idx].token = token
            if updateExistingSource {
                accounts[idx].authSource = authSource
            }
            try persist(accounts[idx])
            return CodexAuthImportResult(account: accounts[idx], didUpdate: true)
        }

        let account = OAuthAccount(
            label: email ?? "Current Codex Login",
            provider: .codex,
            email: email,
            externalID: externalID,
            token: token,
            authSource: authSource
        )

        try persist(account)
        accounts.append(account)
        return CodexAuthImportResult(account: account, didUpdate: false)
    }

    private func importCodexMultiAuthAccountsIfNeeded() {
        let multiAuthURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("multi-auth")
            .appendingPathComponent("openai-codex-accounts.json")

        guard let data = try? Data(contentsOf: multiAuthURL),
              let store = try? JSONDecoder().decode(CodexMultiAuthStore.self, from: data) else {
            return
        }

        for item in store.accounts where item.enabled {
            let alreadyImported = accounts.contains { account in
                account.provider == .codex
                    && (
                        account.externalID == item.accountID
                        || (item.email != nil && account.email == item.email)
                    )
            }
            guard !alreadyImported else { continue }

            let expiresAt = item.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            let createdAt = Date(timeIntervalSince1970: TimeInterval(item.addedAt ?? Int64(Date().timeIntervalSince1970 * 1000)) / 1000)
            let account = OAuthAccount(
                label: item.accountLabel ?? item.email ?? "Codex Account",
                provider: .codex,
                email: item.email,
                externalID: item.accountID,
                token: OAuthToken(
                    accessToken: item.accessToken,
                    refreshToken: item.refreshToken,
                    expiresAt: expiresAt,
                    scope: nil
                ),
                createdAt: createdAt,
                authSource: .json
            )

            do {
                try persist(account)
                accounts.append(account)
            } catch {
                print("OAuthStore.importCodexMultiAuthAccountsIfNeeded failed: \(error)")
            }
        }
    }

    private func cliProxyAuthDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cli-proxy-api", isDirectory: true)
    }

    private func writeConfigFile(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).coderswitch.bak")
        let temporaryBackupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).coderswitch.bak.\(UUID().uuidString).tmp")
        let hadExistingFile = fm.fileExists(atPath: url.path)

        if hadExistingFile {
            try fm.copyItem(at: url, to: temporaryBackupURL)
        }

        do {
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if hadExistingFile {
                if fm.fileExists(atPath: backupURL.path) {
                    try fm.removeItem(at: backupURL)
                }
                try fm.moveItem(at: temporaryBackupURL, to: backupURL)
            }
        } catch {
            if hadExistingFile, fm.fileExists(atPath: temporaryBackupURL.path) {
                try? fm.removeItem(at: url)
                try? fm.copyItem(at: temporaryBackupURL, to: url)
                try? fm.removeItem(at: temporaryBackupURL)
            }
            throw error
        }
    }

    private func cliProxyCodexFilename(for account: OAuthAccount) -> String {
        let email = account.email ?? account.label
        return "codex-\(safeFilenameComponent(email)).json"
    }

    private func cliProxyGeminiFilename(for account: OAuthAccount) -> String {
        let email = account.email ?? account.label
        return "gemini-\(safeFilenameComponent(email))-all.json"
    }

    private func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._-+"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return name.isEmpty ? UUID().uuidString : name
    }

    private func cliProxyExpiryString(for token: OAuthToken, fallback: Date?) -> String {
        let expiry = token.expiresAt ?? fallback ?? Date().addingTimeInterval(3600)
        return ISO8601DateFormatter().string(from: expiry)
    }
}

enum OAuthError: LocalizedError {
    case missingAuthorizationCode
    case missingPKCEChallenge
    case missingIDToken
    case tokenExchangeFailed
    case tokenRefreshFailed
    case callbackServerFailed
    case cancelled
    case providerError(String)
    case invalidCodexAuthFile
    case unsupportedCodexAuthMode(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthorizationCode: return "No authorization code in callback"
        case .missingPKCEChallenge: return "PKCE challenge not found"
        case .missingIDToken: return "Codex account is missing an id_token and cannot be exported to CLIProxyAPI"
        case .tokenExchangeFailed: return "Failed to exchange code for token"
        case .tokenRefreshFailed: return "Failed to refresh token"
        case .callbackServerFailed: return "Failed to start callback server"
        case .cancelled: return "Authentication cancelled"
        case .providerError(let msg): return "Provider error: \(msg)"
        case .invalidCodexAuthFile: return "That file does not look like a Codex auth.json file"
        case .unsupportedCodexAuthMode(let mode): return "Cannot import Codex auth mode '\(mode)'. Sign in with ChatGPT auth first."
        }
    }
}

struct CodexAuthImportResult {
    let account: OAuthAccount
    let didUpdate: Bool
}

struct CLIProxyCodexAuthFile: Codable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let accountID: String
    let lastRefresh: String
    let email: String?
    let type: String
    let expired: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
        case lastRefresh = "last_refresh"
        case email
        case type
        case expired
    }
}

struct CLIProxyGeminiAuthFile: Codable {
    let token: CLIProxyGeminiToken
    let projectID: String
    let email: String
    let auto: Bool
    let checked: Bool
    let type: String

    enum CodingKeys: String, CodingKey {
        case token
        case projectID = "project_id"
        case email
        case auto
        case checked
        case type
    }
}

struct CLIProxyGeminiToken: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiry: String
    let tokenURI: String
    let clientID: String
    let clientSecret: String
    let scopes: [String]
    let universeDomain: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiry
        case tokenURI = "token_uri"
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case scopes
        case universeDomain = "universe_domain"
    }
}

struct CodexAuthFile: Codable {
    let authMode: String
    let openAIAPIKey: String?
    let tokens: CodexAuthTokens
    let lastRefresh: String
    let email: String?
    let codexMultiAuthSyncVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
        case email
        case codexMultiAuthSyncVersion
    }
}

struct CodexAuthTokens: Codable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }
}

struct CodexAuthClaims {
    let email: String?
    let accountID: String?
    let expiresAt: Date?
    let scope: String?

    static func fromIDToken(_ idToken: String) -> CodexAuthClaims? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2,
              let payload = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }

        let profile = object["https://api.openai.com/profile"] as? [String: Any]
        let auth = object["https://api.openai.com/auth"] as? [String: Any]
        let expiresAt = (object["exp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let scopes = (object["scp"] as? [String])?.joined(separator: " ")

        return CodexAuthClaims(
            email: profile?["email"] as? String,
            accountID: auth?["chatgpt_account_id"] as? String,
            expiresAt: expiresAt,
            scope: scopes
        )
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

struct CodexMultiAuthStore: Decodable {
    let accounts: [CodexMultiAuthAccount]
}

struct CodexMultiAuthAccount: Decodable {
    let accountID: String
    let accountLabel: String?
    let email: String?
    let refreshToken: String?
    let accessToken: String
    let expiresAt: Int64?
    let enabled: Bool
    let addedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case accountLabel
        case email
        case refreshToken
        case accessToken
        case expiresAt
        case enabled
        case addedAt
    }
}

extension URLSession {
    static func urlEncodedForm(_ dict: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = dict.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
