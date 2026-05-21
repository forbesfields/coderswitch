# CoderSwitch — Progress

A self-hosted macOS menu bar app for managing AI subscriptions and API keys across providers. Stores credentials, runs a local proxy for Claude Code/Codex, and shows usage limits at a glance.

## What this is

One place for:
- OAuth tokens (Google Gemini, Codex) with quick switching
- API keys with custom endpoints (OpenRouter, MiniMax, Chinese proxies like ikuncode.cc, fishxcode.com)
- Multiple accounts per provider (e.g. 2 Google AI Pro accounts)
- Usage/quota visibility in the menu bar
- Single OpenAI- and Anthropic-compatible local proxy URL to point Claude Code/Codex at

## Stack

- **Language**: Swift 6 (strict concurrency)
- **UI**: SwiftUI, MenuBarExtra
- **Project gen**: XcodeGen
- **HTTP server**: [Hummingbird](https://github.com/hummingbird-project/hummingbird) 2.x (Swift, async, SSE streaming)
- **HTTP client**: URLSession (built-in)
- **Persistence**: GRDB/SQLite in `~/Library/Application Support/CoderSwitch/`; API keys and OAuth tokens encrypted with CryptoKit `SecretBox`
- **Platform**: macOS 14+ (LSUIElement menu bar app)

## What's Done

### Phase 1 — Foundation
- [x] Directory + PROGRESS.md
- [x] XcodeGen `project.yml` (Hummingbird 2.x SPM dep, macOS 14+, strict concurrency)
- [x] Minimal menu bar app (MenuBarExtra with `switch.2` icon, LSUIElement=true)
- [x] Data models: `Account`, `Provider`, `APICompatibility`, `UsageLimit`
- [x] Persistence: `AccountStore`, `OAuthStore`, and `ProxySettings` backed by GRDB/SQLite with encrypted credential blobs

### Phase 2 — Add Accounts
- [x] Settings window (TabView: Accounts tab + Proxy tab)
- [x] AddAccountView: provider picker, label, API key (SecureField), optional custom endpoint
- [x] Accounts listed by provider in both popover and settings
- [x] Delete account (removes the encrypted API-key row from SQLite)
- [x] Per-provider config: OpenAI/Anthropic compat, default endpoint, custom endpoint override
- [x] Provider routing slugs: `openrouter`, `minimax`, `ikuncode`, `fishxcode`, `openai`, `anthropic`

### Phase 3 — Proxy Server
- [x] Hummingbird HTTP server, configurable port (default 8484)
- [x] Admin API key (auto-generated `cs-<base64>`, regeneratable, constant-time comparison)
- [x] `GET /healthz` → `{"ok":true}`
- [x] `GET /v1/models` → list of `{id: "slug:label", object: "model", owned_by}`
- [x] `POST /v1/chat/completions` → OpenAI-compatible forwarding with model routing
- [x] `POST /v1/messages` → Anthropic-compatible forwarding with `x-api-key` + `anthropic-version`
- [x] Auth: `Authorization: Bearer <adminKey>` or `x-api-key: <adminKey>`
- [x] Model routing: `minimax/MiniMax-M2.7`, `openrouter:work/anthropic/claude-3-opus`, bare model names
- [x] SSE streaming pass-through (URLSession.AsyncBytes → Hummingbird ResponseBody async sequence)
- [x] Hop-by-hop header stripping (transfer-encoding, content-encoding, connection)
- [x] 16MB body limit on incoming requests
- [x] ProxyManager: @Observable lifecycle (start/stop/restart, status enum with port, failed message)
- [x] ProxySettings: persisted to SQLite, port/adminKey/autoStart computed
- [x] AppContext: owns everything, triggers autostart + quota polling on launch
- [x] Diagnostic stderr breadcrumbs at every lifecycle point for silent-failure debugging

### Phase 4 — Quota Polling (partial)
- [x] QuotaPoller: 60s interval, parallel per-account, manual refresh button in popover
- [x] QuotaCheck pattern: per-provider path + parser, extensible
- [x] OpenRouter: `GET /api/v1/credits` → dollar balance parsed into UsageLimit bars
- [x] MiniMax: `GET /v1/token_plan/remains` → model request windows parsed into UsageLimit bars
- [x] OpenRouter balance: `GET /api/v1/credits` confirmed supported by API key and used for account credits/usage
- [x] UsageLimit model: name, used, limit, unit, resetAt, computed fraction + remainingDescription
- [x] Account.usageLimits + lastCheckedAt + lastCheckError persisted to SQLite
- [x] Popover: per-account usage bars (green/yellow/red), error text, "No quota endpoint" label
- [x] Verified live: OpenRouter key polled successfully, usage displayed

### End-to-end verified
- [x] MiniMax streaming: `curl -H "Authorization: Bearer <admin>" -d '{"model":"minimax/MiniMax-M2.7","stream":true,...}'` → SSE chunks arrive incrementally through proxy
- [x] Multiple accounts visible in popover, grouped by provider

## What's In Progress

### OAuth System
- [x] OAuthProvider enum (Codex uses OpenAI auth.openai.com + Gemini uses Google OAuth)
- [x] OAuthAccount model with token storage
- [x] PKCE challenge generation with S256 method
- [x] Localhost callback server (NWListener on port 1455) for OAuth responses
- [x] OAuthStore with token exchange + refresh
- [x] Quick switch UI in popover (expandable section)
- [x] OAuth tab in Settings window
- [x] Account switching writes to ~/.codex/config.json (Codex) and ~/.gemini/.env (Gemini)
- [x] Token refresh on demand
- [ ] Test with real OAuth flows (Gemini requires Google Cloud client ID)

### Token counter
- [x] Persist per-account daily token buckets: requests, input tokens, output tokens, cache read, cache write, uncategorized tokens
- [x] Parse usage from non-streaming responses + SSE `usage` chunks (OpenAI + Anthropic shapes)
- [x] Add daily, weekly, monthly, yearly, and all-time rollups
- [x] Track and display rollups by provider and by model
- [x] Surface aggregate counter in popover + detailed Usage tab in Settings

### Provider model selection
- [x] Fetch provider models from each account's `/models` endpoint
- [x] Persist fetched model list + default model per account
- [x] Expose fetched models from local `/v1/models` as `provider:account/model-id`
- [x] Route `provider:account` alias to the selected default model

## What's Not Done

### Phase 5 — OAuth
- [x] Google Gemini OAuth 2.0 + PKCE
- [x] Codex OAuth 2.0 + PKCE
- [x] Multiple OAuth accounts per provider
- [x] Quick account switching (Codex CLI config + Gemini/antigravity env var)
- [x] Token refresh on demand
- [ ] Google AI OAuth (uses Gemini - same system)
- [ ] Claude OAuth (via claude.ai/oauth/authorize)

### Phase 6 — Polish + Release
- [x] App icon (custom CoderSwitch AppIcon asset catalog; menu bar uses separate template image)
- [x] About window with version
- [x] README with setup instructions
- [x] MIT LICENSE and SECURITY.md for GitHub publishing
- [x] Config backup/restore: Settings → Backup exports/imports accounts, API keys, OAuth tokens, proxy settings, and account usage/default-model metadata as a `.coderswitchconfig` JSON file
- [x] User data wipe: Settings → Backup can delete local accounts, API keys, OAuth tokens, proxy settings, and request logs after confirmation
- [ ] Notarized DMG / GitHub Release
- [ ] Quota checkers for: ikuncode.cc, fishxcode.com

## Source Map

```
CoderSwitch/
  App/
    AppContext.swift          — @Observable container, owns all services, triggers autostart + polling
    CoderSwitchApp.swift     — @main, MenuBarExtra + Settings window, injects environments
  Models/
    Account.swift             — Account struct (id, label, provider, customEndpoint, usageLimits, lastCheckedAt)
    OAuthAccount.swift        — OAuth-specific account with token info
    OAuthProvider.swift       — Enum for Codex + Gemini providers
    OAuthToken.swift          — OAuth access/refresh token with expiry
    PKCEChallenge.swift       — PKCE code challenge/verifier generation
    Provider.swift            — Provider enum (openRouter, miniMax, ikunCode, fishXCode, openAICompatible, anthropicCompatible)
    QuotaCheck.swift          — QuotaCheck struct (path + parser), OpenRouter implementation
    TokenUsage.swift          — Token usage buckets, period rollups, parser for JSON/SSE usage metadata
    UsageLimit.swift          — UsageLimit struct (name, used, limit, unit, resetAt, computed fraction)
  Proxy/
    ModelRouter.swift          — Resolves "slug:label/model" strings to (Account, upstreamModel)
    ProxyManager.swift         — @Observable lifecycle: start/stop/restart, status, diagnostics breadcrumbs
    ProxyServer.swift          — Hummingbird Application with /healthz, /v1/models, /v1/chat/completions, /v1/messages
    ProxySettings.swift        — @Observable persisted settings (port, adminKey, autoStart, baseURL)
    ProxyState.swift           — actor ProxyState: Sendable snapshot for request handlers
    QuotaPoller.swift          — @Observable timer: parallel per-account quota fetch, refresh button
    TokenUsageRecorder.swift   — actor bridge from proxy streams back to AccountStore persistence
    UsageTrackingStream.swift  — ByteStream wrapper that preserves streaming while recording token usage
    UpstreamForwarder.swift    — URLSession.bytes wrapper, hop-by-hop header stripping, ByteStream async sequence
  Stores/
    AccountStore.swift         — @Observable SQLite persistence + encrypted API-key CRUD
    ConfigBackupStore.swift    — Full config archive export/import helpers
    KeychainStore.swift        — Security.framework generic-password wrapper
    OAuthStore.swift            — OAuth account storage, token refresh, account switching
    OAuthCallbackHandler.swift — Handles OAuth callback URLs (coderswitch:// scheme)
  Views/
    AddAccountView.swift       — Form: provider picker, label, API key, custom endpoint
    OAuthAccountsTab.swift      — OAuth account management in Settings
    SettingsWindow.swift       — TabView: Accounts + OAuth + Proxy + Usage + Backup tabs
    StatusPopover.swift        — Menu bar popover: proxy, OAuth quick switch, per-account usage
```

## Architecture

```
┌──────────────────────────────────────────┐
│  Menu Bar App (SwiftUI)                  │
│  ┌────────────────────────────────────┐  │
│  │ StatusPopover                      │  │
│  │  ▸ Proxy: running :8484 █        │  │
│  │  ▸ OpenRouter                      │  │
│  │    or: Credits 3/10 ████░░        │  │
│  │  ▸ MiniMax                         │  │
│  │    minimaxtoken: weekly 13846/15000│  │
│  │  [Refresh] Settings Quit          │  │
│  └────────────────────────────────────┘  │
│                                          │
│  Settings Window (Accounts + Proxy tabs) │
└──────────────────┬───────────────────────┘
                   │ manages
┌──────────────────▼───────────────────────┐
│  ProxyServer (Hummingbird :8484)          │
│  Auth: Bearer <adminKey>                  │
│  /v1/chat/completions → upstream (OpenAI) │
│  /v1/messages         → upstream (Anthropic) │
│  /v1/models           → from AccountStore  │
└───────────────────────────────────────────┘
```

## Key Decisions

- **Provider prefix routing** (`minimax/MiniMax-M2.7`, `openrouter:work/...`): explicit, matches existing tools like litellm
- **All-Swift instead of Go binary**: simpler build, single language, no cross-compile or process management
- **Encrypted SQLite for app state**: simple local persistence, with a remaining hardening item to move the `SecretBox` root key out of the app data directory before broad distribution
- **QuotaCheck protocol pattern**: each provider declares its own path + JSON parser, keeping polling logic generic
- **SSE pass-through via async sequence**: no buffering, chunks arrive as they come from upstream

## Suggestions / Next Steps

1. **Token counter validation**: Exercise the proxy against a few real providers and confirm their streaming usage metadata shapes are counted once. Current parser handles standard OpenAI `usage`, Anthropic `message.usage` / `usage`, and final SSE usage events.

2. **More provider quota checkers**: ikuncode.cc and fishxcode.com don't have documented quota APIs — may need to scrape dashboard HTML or skip them. Consider marking providers without quota endpoints gracefully in the UI (already done: "No quota endpoint" label).

3. **Secret storage hardening**: `SecretBox` encrypts credential blobs, but its root key still lives in Application Support. For a public release, migrate that key to Keychain or clearly document the local-tool threat model.

4. **OAuth**: Defer to after v1. Each provider has its own flow, some require PKCE, and ChatGPT doesn't have a documented public OAuth endpoint. The current API-key-only flow covers the primary use case.

5. **Portfolio polish before release**: App icon, screenshots for README, GitHub Release with notarized DMG. This is a portfolio piece — first impression matters.
