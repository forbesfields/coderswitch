import Foundation

/// Resolves an incoming request's model string to a backing Account.
///
/// Model strings can be prefixed to disambiguate which account to use:
///   "openrouter/anthropic/claude-3-opus" → first OpenRouter account, model "anthropic/claude-3-opus"
///   "openrouter:work/anthropic/claude-3-opus" → OpenRouter account labeled "work"
///   "anthropic/claude-3-opus" → first Anthropic-compatible account, model "anthropic/claude-3-opus"
/// If no provider prefix is found, the first account whose default endpoint accepts the request is used.
struct ModelRouter {
    let accounts: [Account]

    struct Resolution {
        let account: Account
        let upstreamModel: String
    }

    func resolve(
        model: String,
        compatibility: APICompatibility,
        preferredAccountID: UUID? = nil
    ) -> Resolution? {
        if let preferredAccountID,
           let account = accounts.first(where: { $0.id == preferredAccountID }) {
            return resolvePreferred(model: model, compatibility: compatibility, account: account)
        }

        if let slash = model.firstIndex(of: "/") {
            let prefix = String(model[..<slash])
            let rest = String(model[model.index(after: slash)...])
            if let account = matchAccount(prefix: prefix, compatibility: compatibility) {
                return Resolution(account: account, upstreamModel: rest)
            }
        }
        if let account = matchAccount(prefix: model, compatibility: compatibility),
           let defaultModel = account.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultModel.isEmpty {
            return Resolution(account: account, upstreamModel: defaultModel)
        }
        if let account = accounts.first(where: {
            $0.isEnabled && $0.provider.isProxyRoutable && $0.provider.compatibility == compatibility
        }) {
            return Resolution(account: account, upstreamModel: model)
        }
        return nil
    }

    func resolveDefault(
        compatibility: APICompatibility,
        preferredAccountID: UUID? = nil
    ) -> Resolution? {
        if let preferredAccountID,
           let account = accounts.first(where: {
               $0.id == preferredAccountID
                   && $0.isEnabled
                   && $0.provider.isProxyRoutable
                   && $0.provider.compatibility == compatibility
           }) {
            return Resolution(account: account, upstreamModel: account.defaultModel ?? "")
        }
        guard let account = accounts.first(where: {
            $0.isEnabled && $0.provider.isProxyRoutable && $0.provider.compatibility == compatibility
        }) else {
            return nil
        }
        return Resolution(account: account, upstreamModel: account.defaultModel ?? "")
    }

    private func resolvePreferred(
        model: String,
        compatibility: APICompatibility,
        account: Account
    ) -> Resolution? {
        guard account.isEnabled,
              account.provider.isProxyRoutable,
              account.provider.compatibility == compatibility else {
            return nil
        }

        if let slash = model.firstIndex(of: "/") {
            let prefix = String(model[..<slash])
            let rest = String(model[model.index(after: slash)...])
            if matches(account: account, prefix: prefix, compatibility: compatibility) {
                return Resolution(account: account, upstreamModel: rest)
            }
        }

        if matches(account: account, prefix: model, compatibility: compatibility),
           let defaultModel = account.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultModel.isEmpty {
            return Resolution(account: account, upstreamModel: defaultModel)
        }

        return Resolution(account: account, upstreamModel: model)
    }

    private func matchAccount(prefix: String, compatibility: APICompatibility) -> Account? {
        let parts = prefix.split(separator: ":", maxSplits: 1).map(String.init)
        let providerSlug = parts[0].lowercased()
        let labelHint = parts.count > 1 ? parts[1].lowercased() : nil

        let candidates = accounts.filter { account in
            guard account.isEnabled else { return false }
            guard account.provider.compatibility == compatibility else { return false }
            guard account.provider.isProxyRoutable else { return false }
            return account.provider.routingSlug == providerSlug
        }
        guard !candidates.isEmpty else { return nil }
        if let labelHint {
            return candidates.first { $0.label.lowercased() == labelHint }
                ?? candidates.first { $0.label.lowercased().contains(labelHint) }
        }
        return candidates.first
    }

    private func matches(account: Account, prefix: String, compatibility: APICompatibility) -> Bool {
        let parts = prefix.split(separator: ":", maxSplits: 1).map(String.init)
        let providerSlug = parts[0].lowercased()
        let labelHint = parts.count > 1 ? parts[1].lowercased() : nil
        guard account.isEnabled,
              account.provider.compatibility == compatibility,
              account.provider.isProxyRoutable,
              account.provider.routingSlug == providerSlug else {
            return false
        }
        guard let labelHint else { return true }
        let label = account.label.lowercased()
        return label == labelHint || label.contains(labelHint)
    }
}

extension Provider {
    /// Slug used as a model prefix to route to this provider type.
    var routingSlug: String {
        switch self {
        case .codex: "codex"
        case .openAI: "openai-direct"
        case .anthropic: "anthropic-direct"
        case .openRouter: "openrouter"
        case .miniMax: "minimax"
        case .ikunCode: "ikuncode"
        case .fishXCode: "fishxcode"
        case .openAICompatible: "openai"
        case .anthropicCompatible: "anthropic"
        case .googleAntigravity: "antigravity"
        }
    }
}
