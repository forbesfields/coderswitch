import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

/// Hummingbird-based local proxy. Wraps an Application running on 127.0.0.1.
/// Lifecycle is managed by ProxyManager — this type only knows how to construct + run.
struct ProxyServer {
    let port: Int
    let state: ProxyState
    let forwarder: UpstreamForwarder

    init(port: Int, state: ProxyState, forwarder: UpstreamForwarder = .init()) {
        self.port = port
        self.state = state
        self.forwarder = forwarder
    }

    func runUntilCancelled() async throws {
        let router = Router()
        let state = self.state
        let forwarder = self.forwarder

        router.get("/healthz") { _, _ in
            Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: #"{"ok":true}"#))
            )
        }

        router.get("/v1/models") { request, _ in
            try await Self.handleModels(request: request, state: state)
        }

        router.post("/v1/chat/completions") { request, context in
            try await Self.handleOpenAIChat(request: request, context: context, state: state, forwarder: forwarder)
        }

        router.post("/v1/responses") { request, context in
            try await Self.handleOpenAIModelRequest(
                request: request,
                context: context,
                state: state,
                forwarder: forwarder,
                upstreamPath: "/responses"
            )
        }

        router.post("/v1/responses/compact") { request, context in
            try await Self.handleOpenAIModelRequest(
                request: request,
                context: context,
                state: state,
                forwarder: forwarder,
                upstreamPath: "/responses/compact"
            )
        }

        router.get("/v1/responses/*") { request, context in
            try await Self.handleOpenAIPassthrough(request: request, context: context, state: state, forwarder: forwarder)
        }

        router.post("/v1/responses/*") { request, context in
            try await Self.handleOpenAIPassthrough(request: request, context: context, state: state, forwarder: forwarder)
        }

        router.post("/v1/messages") { request, context in
            try await Self.handleAnthropicMessages(request: request, context: context, state: state, forwarder: forwarder)
        }

        router.post("/v1/messages/count_tokens") { request, context in
            try await Self.handleAnthropicMessages(
                request: request,
                context: context,
                state: state,
                forwarder: forwarder,
                upstreamPath: "/messages/count_tokens"
            )
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port),
                serverName: "CoderSwitch"
            )
        )
        try await app.runService()
    }

    // MARK: handlers

    private static func handleModels(
        request: Request,
        state: ProxyState
    ) async throws -> Response {
        let snap = await state.snapshot()
        _ = try authorize(request: request, adminKey: snap.adminKey)

        struct Model: Encodable {
            let id: String
            let object = "model"
            let owned_by: String
        }
        struct ModelsList: Encodable {
            let object = "list"
            let data: [Model]
        }

        let models = snap.accounts.filter { $0.provider.isProxyRoutable }.flatMap { acct in
            var accountModels: [Model] = []
            let alias = "\(acct.provider.routingSlug):\(acct.label.lowercased())"
            if acct.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                accountModels.append(Model(id: alias, owned_by: acct.provider.displayName))
            }
            for model in acct.availableModels ?? [] {
                accountModels.append(Model(
                    id: "\(alias)/\(model.id)",
                    owned_by: model.ownedBy ?? acct.provider.displayName
                ))
            }
            if accountModels.isEmpty {
                accountModels.append(Model(id: alias, owned_by: acct.provider.displayName))
            }
            return accountModels
        }
        let payload = try JSONEncoder().encode(ModelsList(data: models))
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: payload))
        )
    }

    private static func handleOpenAIChat(
        request: Request,
        context: some RequestContext,
        state: ProxyState,
        forwarder: UpstreamForwarder
    ) async throws -> Response {
        try await handleOpenAIModelRequest(
            request: request,
            context: context,
            state: state,
            forwarder: forwarder,
            upstreamPath: "/chat/completions"
        )
    }

    private static func handleOpenAIModelRequest(
        request: Request,
        context: some RequestContext,
        state: ProxyState,
        forwarder: UpstreamForwarder,
        upstreamPath: String
    ) async throws -> Response {
        let startedAt = Date()
        let snap = await state.snapshot()
        let auth = try authorize(request: request, adminKey: snap.adminKey)

        let bodyBuf = try await request.body.collect(upTo: 16 * 1024 * 1024)
        let bodyData = Data(buffer: bodyBuf)
        let model = try extractModel(from: bodyData)

        let router = ModelRouter(accounts: snap.accounts)
        guard let resolved = router.resolve(
            model: model,
            compatibility: .openAI,
            preferredAccountID: auth.preferredAccountID
        ) else {
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: "POST",
                path: request.uri.path,
                model: model,
                statusCode: 502,
                message: "no OpenAI-compatible account matches model '\(model)'"
            )
            throw HTTPError(.badGateway, message: "no account matches model '\(model)'")
        }
        guard let apiKey = snap.apiKeys[resolved.account.id] else {
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: "POST",
                path: request.uri.path,
                model: model,
                account: resolved.account,
                upstreamModel: resolved.upstreamModel,
                statusCode: 502,
                message: "missing api key for account"
            )
            throw HTTPError(.badGateway, message: "missing api key for account")
        }

        let rewritten = rewriteModel(in: bodyData, to: resolved.upstreamModel)
        let url = try buildURL(base: resolved.account.endpoint, path: upstreamPath, query: request.uri.query)

        let forwardHeaders: [(String, String)] = [
            ("Authorization", "Bearer \(apiKey)"),
            ("Content-Type", request.headers[.contentType] ?? "application/json"),
            ("Accept", request.headers[.accept] ?? "application/json"),
        ]

        return try await proxyResponse(
            forwarder: forwarder,
            state: state,
            account: resolved.account,
            model: resolved.upstreamModel,
            requestedModel: model,
            method: "POST",
            path: request.uri.path,
            startedAt: startedAt,
            url: url,
            headers: forwardHeaders,
            body: rewritten
        )
    }

    private static func handleOpenAIPassthrough(
        request: Request,
        context: some RequestContext,
        state: ProxyState,
        forwarder: UpstreamForwarder
    ) async throws -> Response {
        let startedAt = Date()
        let snap = await state.snapshot()
        let auth = try authorize(request: request, adminKey: snap.adminKey)
        let router = ModelRouter(accounts: snap.accounts)

        guard let resolved = router.resolveDefault(compatibility: .openAI, preferredAccountID: auth.preferredAccountID) else {
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: requestMethodName(request),
                path: request.uri.path,
                statusCode: 502,
                message: "no OpenAI-compatible account available"
            )
            throw HTTPError(.badGateway, message: "no OpenAI-compatible account available")
        }
        guard let apiKey = snap.apiKeys[resolved.account.id] else {
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: requestMethodName(request),
                path: request.uri.path,
                account: resolved.account,
                upstreamModel: resolved.upstreamModel,
                statusCode: 502,
                message: "missing api key for account"
            )
            throw HTTPError(.badGateway, message: "missing api key for account")
        }

        let bodyBuf = try await request.body.collect(upTo: 16 * 1024 * 1024)
        let bodyData = Data(buffer: bodyBuf)
        let upstreamPath = stripV1Prefix(request.uri.path)
        let url = try buildURL(base: resolved.account.endpoint, path: upstreamPath, query: request.uri.query)
        var forwardHeaders: [(String, String)] = [
            ("Authorization", "Bearer \(apiKey)"),
            ("Accept", request.headers[.accept] ?? "application/json"),
        ]
        if !bodyData.isEmpty {
            forwardHeaders.append(("Content-Type", request.headers[.contentType] ?? "application/json"))
        }

        return try await proxyResponse(
            forwarder: forwarder,
            state: state,
            account: resolved.account,
            model: resolved.upstreamModel,
            requestedModel: nil,
            method: requestMethodName(request),
            path: request.uri.path,
            startedAt: startedAt,
            url: url,
            headers: forwardHeaders,
            body: bodyData.isEmpty ? nil : bodyData
        )
    }

    private static func handleAnthropicMessages(
        request: Request,
        context: some RequestContext,
        state: ProxyState,
        forwarder: UpstreamForwarder,
        upstreamPath: String = "/messages"
    ) async throws -> Response {
        let startedAt = Date()
        let snap = await state.snapshot()
        let auth = try authorize(request: request, adminKey: snap.adminKey)

        let bodyBuf = try await request.body.collect(upTo: 16 * 1024 * 1024)
        let bodyData = Data(buffer: bodyBuf)
        let model = try extractModel(from: bodyData)

        let router = ModelRouter(accounts: snap.accounts)
        let resolved: ModelRouter.Resolution
        if let preferredAccountID = auth.preferredAccountID {
            guard let account = snap.accounts.first(where: {
                $0.id == preferredAccountID && $0.isEnabled && $0.provider.isClaudeCodeCompatible
            }) else {
                await recordFailedRequest(
                    state: state,
                    startedAt: startedAt,
                    method: "POST",
                    path: request.uri.path,
                    model: model,
                    statusCode: 502,
                    message: "selected Claude Code account is unavailable"
                )
                throw HTTPError(.badGateway, message: "selected Claude Code account is unavailable")
            }
            resolved = ModelRouter.Resolution(account: account, upstreamModel: model)
        } else {
            guard let routed = router.resolve(model: model, compatibility: .anthropic) else {
                await recordFailedRequest(
                    state: state,
                    startedAt: startedAt,
                    method: "POST",
                    path: request.uri.path,
                    model: model,
                    statusCode: 502,
                    message: "no Anthropic account matches model '\(model)'"
                )
                throw HTTPError(.badGateway, message: "no Anthropic account matches model '\(model)'")
            }
            resolved = routed
        }
        guard let apiKey = snap.apiKeys[resolved.account.id] else {
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: "POST",
                path: request.uri.path,
                model: model,
                account: resolved.account,
                upstreamModel: resolved.upstreamModel,
                statusCode: 502,
                message: "missing api key for account"
            )
            throw HTTPError(.badGateway, message: "missing api key for account")
        }

        let rewritten = rewriteModel(in: bodyData, to: resolved.upstreamModel)
        let url = try buildURL(base: resolved.account.endpoint, path: upstreamPath, query: request.uri.query)

        let forwardHeaders: [(String, String)] = [
            ("x-api-key", apiKey),
            ("anthropic-version", request.headers[HTTPField.Name("anthropic-version")!] ?? "2023-06-01"),
            ("Content-Type", request.headers[.contentType] ?? "application/json"),
            ("Accept", request.headers[.accept] ?? "application/json"),
        ]

        return try await proxyResponse(
            forwarder: forwarder,
            state: state,
            account: resolved.account,
            model: resolved.upstreamModel,
            requestedModel: model,
            method: "POST",
            path: request.uri.path,
            startedAt: startedAt,
            url: url,
            headers: forwardHeaders,
            body: rewritten
        )
    }

    // MARK: helpers

    private struct AuthorizationContext {
        let preferredAccountID: UUID?
    }

    private static func authorize(request: Request, adminKey: String) throws -> AuthorizationContext {
        guard !adminKey.isEmpty else {
            throw HTTPError(.serviceUnavailable, message: "proxy admin key not configured")
        }
        let header = request.headers[.authorization]
            ?? request.headers[HTTPField.Name("x-api-key")!]
        guard let header else {
            throw HTTPError(.unauthorized, message: "missing credentials")
        }
        let presented = header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
        let parts = presented.split(separator: ":", maxSplits: 1).map(String.init)
        guard constantTimeEquals(parts.first ?? "", adminKey) else {
            throw HTTPError(.unauthorized, message: "invalid credentials")
        }
        let preferredAccountID = parts.count == 2 ? UUID(uuidString: parts[1]) : nil
        return AuthorizationContext(preferredAccountID: preferredAccountID)
    }

    private static func extractModel(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String, !model.isEmpty else {
            throw HTTPError(.badRequest, message: "missing 'model' field")
        }
        return model
    }

    private static func rewriteModel(in data: Data, to upstreamModel: String) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        json["model"] = upstreamModel
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    private static func buildURL(base: String, path: String, query: String? = nil) throws -> URL {
        let trimmedBase = base.trimmingCharacters(in: .whitespaces).trimmingSuffix("/")
        let querySuffix = query.map { "?\($0)" } ?? ""
        guard let url = URL(string: trimmedBase + path + querySuffix) else {
            throw HTTPError(.badGateway, message: "invalid upstream URL")
        }
        return url
    }

    private static func stripV1Prefix(_ path: String) -> String {
        guard path.hasPrefix("/v1/") else { return path }
        return "/" + path.dropFirst(4)
    }

    private static func requestMethodName(_ request: Request) -> String {
        String(describing: request.method).uppercased()
    }

    private static func recordFailedRequest(
        state: ProxyState,
        startedAt: Date,
        method: String,
        path: String,
        model: String? = nil,
        account: Account? = nil,
        upstreamModel: String? = nil,
        statusCode: Int?,
        message: String
    ) async {
        let latencyMS = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        await state.recordRequestLog(ProxyRequestLog(
            timestamp: startedAt,
            method: method,
            path: path,
            accountID: account?.id,
            accountLabel: account?.label,
            provider: account?.provider,
            model: model,
            upstreamModel: upstreamModel,
            statusCode: statusCode,
            latencyMS: latencyMS,
            errorMessage: message
        ))
    }

    private static func proxyResponse(
        forwarder: UpstreamForwarder,
        state: ProxyState,
        account: Account,
        model: String,
        requestedModel: String?,
        method: String,
        path: String,
        startedAt: Date,
        url: URL,
        headers: [(String, String)],
        body: Data?
    ) async throws -> Response {
        let upstream: UpstreamForwarder.Forwarded
        do {
            upstream = try await forwarder.forward(method: method, url: url, headers: headers, body: body)
        } catch {
            await state.recordFailure(accountID: account.id)
            await recordFailedRequest(
                state: state,
                startedAt: startedAt,
                method: method,
                path: path,
                model: requestedModel,
                account: account,
                upstreamModel: model,
                statusCode: 502,
                message: "upstream connect failed: \(error.localizedDescription)"
            )
            throw HTTPError(.badGateway, message: "upstream connect failed: \(error.localizedDescription)")
        }
        if upstream.status >= 500 {
            await state.recordFailure(accountID: account.id)
        }

        var responseHeaders = HTTPFields()
        for (k, v) in upstream.headers {
            if let name = HTTPField.Name(k) {
                responseHeaders.append(HTTPField(name: name, value: v))
            }
        }
        let contentType = upstream.headers.first { $0.0.caseInsensitiveCompare("content-type") == .orderedSame }?.1
        let body = UsageTrackingStream(
            base: upstream.body,
            state: state,
            accountID: account.id,
            provider: account.provider,
            model: model,
            contentType: contentType,
            requestLogContext: ProxyRequestLogContext(
                startedAt: startedAt,
                method: method,
                path: path,
                accountLabel: account.label,
                requestedModel: requestedModel ?? "",
                statusCode: upstream.status
            )
        )
        let status = HTTPResponse.Status(code: upstream.status)
        return Response(
            status: status,
            headers: responseHeaders,
            body: .init(asyncSequence: body)
        )
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
