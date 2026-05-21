# CC-Switch Analysis for CoderSwitch Implementation

A comprehensive guide to implementing CC-Switch-like functionality in CoderSwitch.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Models](#2-data-models)
3. [Provider Management](#3-provider-management)
4. [Switching Mechanism](#4-switching-mechanism)
5. [Proxy Service](#5-proxy-service)
6. [Database Schema](#6-database-schema)
7. [Provider Presets](#7-provider-presets)
8. [System Tray](#8-system-tray)
9. [Usage Tracking](#9-usage-tracking)
10. [API Routing](#10-api-routing)
11. [Implementation Recommendations](#11-implementation-recommendations)

---

## 1. Architecture Overview

### Stack Comparison

| Aspect | CC-Switch | CoderSwitch |
|--------|-----------|-------------|
| Platform | Tauri 2 (Rust + React) | Swift 6 (SwiftUI) |
| Backend | Rust with Tauri IPC | Hummingbird 2.x |
| Database | SQLite | JSON + Keychain |
| UI | React + TanStack Query | SwiftUI |
| Config Storage | Live config files + DB | Local proxy + JSON |

### Key Insight

CC-Switch writes configuration to **each CLI tool's native config file**. CoderSwitch uses a **local proxy as the single endpoint**, which is simpler - you just route requests through the proxy.

---

## 2. Data Models

### Provider Structure (CC-Switch)

```typescript
// TypeScript frontend
interface Provider {
  id: string;
  name: string;
  settingsConfig: Record<string, any>;  // App-specific config
  websiteUrl?: string;
  category?: ProviderCategory;
  createdAt?: number;
  sortIndex?: number;
  notes?: string;
  isPartner?: boolean;
  meta?: ProviderMeta;
  icon?: string;
  iconColor?: string;
  inFailoverQueue?: boolean;
}

type ProviderCategory =
  | "official"
  | "cn_official"
  | "cloud_provider"
  | "aggregator"
  | "third_party"
  | "custom"
  | "omo"
  | "omo-slim";
```

### ProviderMeta (Frontend-Only Data)

```typescript
interface ProviderMeta {
  custom_endpoints?: Record<string, CustomEndpoint>;
  commonConfigEnabled?: boolean;
  claudeDesktopMode?: "direct" | "proxy";
  claudeDesktopModelRoutes?: Record<string, ClaudeDesktopModelRoute>;
  usage_script?: UsageScript;
  endpointAutoSelect?: boolean;
  isPartner?: boolean;
  partnerPromotionKey?: string;
  testConfig?: ProviderTestConfig;
  costMultiplier?: string;
  apiFormat?: "anthropic" | "openai_chat" | "openai_responses" | "gemini_native";
  authBinding?: AuthBinding;
  apiKeyField?: "ANTHROPIC_AUTH_TOKEN" | "ANTHROPIC_API_KEY";
  isFullUrl?: boolean;
  promptCacheKey?: string;
  codexFastMode?: boolean;
  providerType?: string;
  liveConfigManaged?: boolean;
}
```

### Rust Backend Provider

```rust
pub struct Provider {
    pub id: String,
    pub name: String,
    pub settings_config: Value,  // JSON blob
    pub website_url: Option<String>,
    pub category: Option<String>,
    pub created_at: Option<i64>,
    pub sort_index: Option<usize>,
    pub notes: Option<String>,
    pub meta: Option<ProviderMeta>,  // NOT written to live config
    pub icon: Option<String>,
    pub icon_color: Option<String>,
    pub in_failover_queue: bool,
}
```

### CoderSwitch Suggested Model

```swift
struct Account: Codable, Identifiable {
    let id: UUID
    var label: String
    var provider: ProviderType  // enum: openRouter, miniMax, ikunCode, etc.
    var apiKeyRef: String       // Keychain reference, not raw key
    var customEndpoint: String?
    var isCurrent: Bool
    var createdAt: Date
    var sortIndex: Int
    var meta: AccountMeta?     // Frontend-only data
}

struct AccountMeta: Codable {
    var apiFormat: APIFormat?
    var usageScript: UsageScript?
    var liveConfigManaged: Bool?
}

enum ProviderType: String, Codable {
    case openRouter = "openrouter"
    case miniMax = "minimax"
    case ikunCode = "ikuncode"
    case fishXCode = "fishxcode"
    case openAICompatible = "openai-compatible"
    case anthropicCompatible = "anthropic-compatible"
}

enum APIFormat: String, Codable {
    case anthropic
    case openAIChat = "openai_chat"
    case openAIResponses = "openai_responses"
}
```

---

## 3. Provider Management

### App-Specific Config Structures

Each CLI tool has its own config format:

| App | Config Location | Key Fields |
|-----|-----------------|------------|
| Claude | `~/.claude/settings.json` | `env: { ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ... }` |
| Codex | `~/.config/hairstyle/config.toml` | `model_provider`, `base_url`, `wire_api` |
| Gemini | `~/.gemini-cli/config.json` | `env: { GEMINI_API_KEY, GOOGLE_GEMINI_BASE_URL }` |
| OpenCode | `~/.config/opencode/opencode.json` | `provider: { npm, options: { baseURL, apiKey }, models }` |
| OpenClaw | `~/.openclaw/openclaw.json` | `baseUrl, apiKey, api, models[]` |

### CoderSwitch Config Structure

Since CoderSwitch uses a proxy, accounts need:

```swift
struct Account {
    let id: UUID
    var label: String                    // Display name
    var provider: ProviderType
    var apiKey: String                  // Stored in Keychain
    var customEndpoint: String?         // Override base URL
    var apiFormat: APIFormat            // For proxy routing
    var defaultModel: String?           // Default model for this account
    var isCurrent: Bool
    var meta: AccountMeta?
}
```

### Dual Storage Pattern

CC-Switch separates concerns:
- **Database/JSON**: Full provider data including meta
- **Live Config**: Only what the CLI tool needs (no meta)

This allows meta (like `usage_script`, `custom_endpoints`) to persist without being written to live configs.

**CoderSwitch equivalent:**
- `AccountStore` (JSON): All account data + meta
- Keychain: API keys only
- No live config files - proxy handles routing

---

## 4. Switching Mechanism

### CC-Switch Switch Flow

```
Frontend: switchProvider(provider)
    ↓
useSwitchProviderMutation.mutateAsync(provider.id)
    ↓
providersApi.switch(providerId, appId)
    ↓
Tauri IPC: switch_provider(id, app)
    ↓
ProviderService::switch(state, app_type, id)
    ↓
[Hot-Switch?] --> Yes --> proxy_service.hot_switch_provider()
    ↓ No
[Normal Switch]
    ↓
1. Backfill current config to DB
2. Update local settings (current_provider)
3. Update database is_current
4. Write to live config file
5. Sync MCP
```

### Hot-Switch vs Normal Switch

**Hot-Switch (Proxy Takeover Mode):**
- When proxy is running + takeover is active
- Updates proxy's in-memory provider map
- No live config write
- Works without CLI restart
- Blocks official providers (account ban risk)

**Normal Switch:**
- Full backfill + write cycle
- May require CLI restart
- Updates MCP config

### CoderSwitch Switch Flow

Since CoderSwitch is proxy-based:

```swift
func switchAccount(_ account: Account) async throws {
    // 1. Update proxy target
    try await proxyManager.setActiveAccount(account)

    // 2. Update database
    for var acc in accounts where acc.isCurrent {
        acc.isCurrent = false
    }
    if let index = accounts.firstIndex(where: { $0.id == account.id }) {
        accounts[index].isCurrent = true
    }
    try accountStore.save(accounts)

    // 3. Update tray menu
    try await updateTrayMenu()
}
```

**Advantages for CoderSwitch:**
- No backfill needed (no live config files)
- No MCP sync (not implementing MCP)
- No restart required (proxy handles routing)
- Instant hot-switch

---

## 5. Proxy Service

### CC-Switch Proxy Architecture

```
Request from Claude/Codex
    ↓
ProxyServer (:15721)
    ↓
ProviderRouter (selects provider based on model)
    ↓
CircuitBreaker (per-provider health)
    ↓
FailoverSwitchManager (auto-switch on failure)
    ↓
Upstream (OpenAI/Anthropic API)
```

### Key Features

1. **Format Conversion**: OpenAI Chat ↔ Anthropic Messages
2. **Hot-Switching**: Update target without restart
3. **Circuit Breaker**: Per-provider failure tracking
4. **Auto-Failover**: Switch to backup on failure
5. **Health Monitoring**: Track provider uptime

### CoderSwitch Proxy Structure

From your PROGRESS.md:

```
┌──────────────────────────────────────────┐
│  ProxyServer (Hummingbird :8484)         │
│  Auth: Bearer <adminKey>                 │
│  /v1/chat/completions → upstream (OpenAI)│
│  /v1/messages         → upstream (Anthropic) │
└───────────────────────────────────────────┘
```

### Provider Routing in CoderSwitch

Model name format from PROGRESS.md:
- `openrouter:label/model` → OpenRouter account
- `minimax:label/MiniMax-M2.7` → MiniMax account
- `provider:label/model` → Custom provider

This allows routing without changing any CLI config - just use the model name in requests.

### Hot-Switch Implementation

```swift
actor ProxyState {
    var currentAccountByProvider: [ProviderType: Account]

    func switchAccount(_ account: Account) {
        currentAccountByProvider[account.provider] = account
    }

    func getUpstream(for model: String) -> (Account, String)? {
        // Parse "provider:label/model" format
        // Return (account, upstreamModel)
    }
}
```

---

## 6. Database Schema

### CC-Switch SQLite Tables

```sql
-- Providers (per-app)
CREATE TABLE providers (
    id TEXT NOT NULL,
    app_type TEXT NOT NULL,
    name TEXT NOT NULL,
    settings_config TEXT NOT NULL,
    website_url TEXT,
    category TEXT,
    created_at INTEGER,
    sort_index INTEGER,
    notes TEXT,
    icon TEXT,
    icon_color TEXT,
    meta TEXT NOT NULL DEFAULT '{}',
    is_current BOOLEAN NOT NULL DEFAULT 0,
    in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
    PRIMARY KEY (id, app_type)
);

-- Proxy Config
CREATE TABLE proxy_config (
    app_type TEXT PRIMARY KEY,
    proxy_enabled INTEGER NOT NULL DEFAULT 0,
    listen_address TEXT NOT NULL DEFAULT '127.0.0.1',
    listen_port INTEGER NOT NULL DEFAULT 15721,
    -- ... circuit breaker config
);

-- Provider Health
CREATE TABLE provider_health (
    provider_id TEXT NOT NULL,
    app_type TEXT NOT NULL,
    is_healthy INTEGER NOT NULL DEFAULT 1,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    last_success_at TEXT,
    last_failure_at TEXT,
    PRIMARY KEY (provider_id, app_type)
);

-- Usage Daily Rollups
CREATE TABLE usage_daily_rollups (
    date TEXT NOT NULL,
    app_type TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    model TEXT NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    total_cost_usd TEXT NOT NULL DEFAULT '0',
    PRIMARY KEY (date, app_type, provider_id, model)
);
```

### CoderSwitch Data Storage

From PROGRESS.md:
- **Non-secret data**: JSON in `~/Library/Application Support/CoderSwitch/`
- **API keys**: macOS Keychain
- **Database**: Not using SQLite

**Suggested schema:**

```swift
// AccountStore.json
struct AccountStore: Codable {
    var accounts: [Account]
    var currentAccountByProvider: [ProviderType: UUID]  // Provider -> Account ID
    var proxySettings: ProxySettings
}

struct ProxySettings: Codable {
    var port: Int = 8484
    var adminKey: String
    var autoStart: Bool = true
    var baseURL: String = "http://localhost"
}
```

---

## 7. Provider Presets

### CC-Switch Preset Structure

```typescript
interface ProviderPreset {
  name: string;
  nameKey?: string;           // i18n key
  websiteUrl: string;
  apiKeyUrl?: string;
  settingsConfig: object;     // Config template
  isOfficial?: boolean;
  isPartner?: boolean;
  partnerPromotionKey?: string;
  category?: ProviderCategory;
  apiKeyField?: "ANTHROPIC_AUTH_TOKEN" | "ANTHROPIC_API_KEY";
  templateValues?: Record<string, TemplateValueConfig>;
  endpointCandidates?: string[];
  theme?: PresetTheme;
  icon?: string;
  iconColor?: string;
  apiFormat?: "anthropic" | "openai_chat" | "openai_responses";
  providerType?: "github_copilot" | "codex_oauth";
  requiresOAuth?: boolean;
  hidden?: boolean;
  modelsUrl?: string;
}
```

### Example Presets

**Claude Official:**
```swift
ProviderPreset(
    name: "Claude Official",
    websiteUrl: "https://www.anthropic.com/claude-code",
    settingsConfig: ["env": [:]],
    isOfficial: true,
    category: .official,
    theme: PresetTheme(icon: "claude", backgroundColor: "#D97757")
)
```

**Shengsuanyun (Aggregator):**
```swift
ProviderPreset(
    name: "Shengsuanyun",
    websiteUrl: "https://www.shengsuanyun.com",
    apiKeyUrl: "https://www.shengsuanyun.com/?from=...",
    settingsConfig: [
        "env": [
            "ANTHROPIC_BASE_URL": "https://router.shengsuanyun.com/api",
            "ANTHROPIC_AUTH_TOKEN": ""
        ]
    ],
    category: .aggregator,
    isPartner: true,
    icon: "shengsuanyun"
)
```

### CoderSwitch Presets

```swift
struct ProviderPreset: Codable {
    let name: String
    let websiteUrl: String
    let apiKeyUrl: String?
    let category: ProviderCategory
    let baseURL: String
    let apiFormat: APIFormat
    let isOfficial: Bool
    let isPartner: Bool
    let iconName: String
    let iconColor: String?
}

let presets: [ProviderPreset] = [
    // OpenRouter
    ProviderPreset(
        name: "OpenRouter",
        websiteUrl: "https://openrouter.ai",
        apiKeyUrl: "https://openrouter.ai/keys",
        category: .aggregator,
        baseURL: "https://openrouter.ai/api/v1",
        apiFormat: .openAIChat,
        isOfficial: false,
        isPartner: false,
        iconName: "globe",
        iconColor: "#4F46E5"
    ),
    // MiniMax
    ProviderPreset(
        name: "MiniMax",
        websiteUrl: "https://platform.minimax.io",
        apiKeyUrl: "https://platform.minimax.io/subscribe/coding-plan",
        category: .aggregator,
        baseURL: "https://api.minimax.chat",
        apiFormat: .anthropic,
        isOfficial: false,
        isPartner: true,
        iconName: "minimax",
        iconColor: "#00A67E"
    ),
    // ... more presets
]
```

---

## 8. System Tray

### CC-Switch Tray Structure

```rust
// Tray menu hierarchy:
// - Show Main Window
// - Open Official Website
// - [App Submenus]
//   - Claude
//     - Provider 1 ✓ (checkmark)
//     - Provider 2
//     - Provider 3
//   - Codex
//     - ...
//   - Gemini
//     - ...
// - Lightweight Mode Toggle
// - Quit
```

### Tray Behavior

1. **Checkmark** on current provider per app
2. **Official providers blocked** when proxy takeover active (with warning emoji)
3. **Usage suffix** appended: `h9% w27%` (hourly/weekly utilization)
4. **Refresh coalescing**: 50ms window to batch rapid updates
5. **Parallel usage fetch**: All visible apps fetched simultaneously

### CoderSwitch Tray Implementation

```swift
struct StatusMenu {
    // Menu bar popover content:
    // ┌────────────────────────────────────┐
    // │ Proxy: running :8484              │
    // ├────────────────────────────────────┤
    // │ ▼ OpenRouter                       │
    // │   ├─ account-1 ✓                  │
    // │   └─ account-2                    │
    // │ ▼ MiniMax                         │
    // │   └─ minimax-main                  │
    // ├────────────────────────────────────┤
    // │ [Refresh] [Settings] [Quit]        │
    // └────────────────────────────────────┘
}

func updateTrayMenu() async {
    // 1. Clear existing menu
    // 2. Add proxy status section
    // 3. For each provider type:
    //    - Create submenu
    //    - Add all accounts with checkmark on current
    // 4. Add action buttons
}
```

### Menu Interaction Pattern

CC-Switch parses tray event ID with prefix:

```rust
// Event ID format: "claude_{provider_id}"
fn parse_tray_event(event_id: &str) -> Option<(AppType, &str)> {
    for section in TRAY_SECTIONS {
        if event_id.starts_with(section.prefix) {
            let provider_id = &event_id[section.prefix.len()..];
            return Some((section.app_type, provider_id));
        }
    }
    None
}
```

---

## 9. Usage Tracking

### CC-Switch Usage Script Pattern

```typescript
interface UsageScript {
  enabled: boolean;
  language: string;           // "javascript" | "typescript"
  code: string;               // The actual script
  timeout?: u64;
  apiKey?: string;            // Override API key
  baseUrl?: string;           // Override base URL
  accessToken?: string;       // OAuth token
  userId?: string;            // User identifier
  templateType?: string;      // Template identifier
  autoQueryInterval?: u64;    // Minutes (0 = disabled)
  codingPlanProvider?: string;
}
```

### Template Types

| Template | Description |
|----------|-------------|
| `github_copilot` | GitHub Copilot quota from OAuth |
| `token_plan` | MiniMax-style token plan |
| `balance` | Anthropic-style balance query |

### Usage Result Structure

```rust
struct UsageResult {
    success: bool,
    data: Option<Vec<UsageData>>,
    error: Option<String>,
}

struct UsageData {
    plan_name: Option<String>,
    total: Option<f64>,
    used: Option<f64>,
    remaining: Option<f64>,
    unit: Option<String>,
    is_valid: Option<bool>,
    invalid_message: Option<String>,
    extra: Option<String>,     // e.g., "Reset: 2024-01-15"
}
```

### CoderSwitch Usage Tracking

From PROGRESS.md - Already implemented:
- `TokenUsageRecorder` actor
- Persists per-account daily token buckets
- Parses usage from non-streaming + SSE responses
- Daily/weekly/monthly/yearly rollups

**What CC-Switch adds:**

```swift
struct QuotaCheck {
    let path: String              // API endpoint path
    let parse: (Data) -> UsageResult  // Parser closure
}

// Example implementations:
let openRouterQuotaCheck = QuotaCheck(
    path: "/api/v1/credits",
    parse: { data in
        // Parse {"balance": 3.50} into UsageData
    }
)

let miniMaxQuotaCheck = QuotaCheck(
    path: "/v1/token_plan/remains",
    parse: { data in
        // Parse model_remains[] into [UsageData]
    }
)
```

---

## 10. API Routing

### Model Routing Format

CC-Switch uses `provider:label/model` format:

| Model Name | Provider Account | Upstream Model |
|------------|-----------------|----------------|
| `minimax:default/MiniMax-M2.7` | MiniMax "default" account | MiniMax-M2.7 |
| `openrouter:work/claude-3-opus` | OpenRouter "work" account | claude-3-opus |
| `openai-compatible:prod/gpt-4o` | Custom "prod" account | gpt-4o |

### Routing Implementation

```swift
struct ModelRouter {
    func route(model: String, accounts: [Account]) -> (Account, String)? {
        // Parse "provider:label/model" or "provider/model"
        let components = model.split(separator: ":")
        guard components.count >= 1 else { return nil }

        let providerPart = String(components[0])
        let rest = components.count > 1 ? String(components[1]) : ""

        // Find matching account
        let account: Account?
        let upstreamModel: String

        if rest.contains("/") {
            // Format: "provider:label/model"
            let parts = rest.split(separator: "/")
            let label = String(parts[0])
            upstreamModel = String(parts[1])
            account = accounts.first { $0.provider.rawValue == providerPart && $0.label == label }
        } else {
            // Format: "provider/model" - use label as first component
            let parts = providerPart.split(separator: "/")
            guard parts.count == 2 else { return nil }
            upstreamModel = String(parts[1])
            account = accounts.first { $0.provider.rawValue == parts[0] && $0.label == String(parts[1]) }
        }

        guard let acc = account else { return nil }
        return (acc, upstreamModel)
    }
}
```

### Request Flow

```
Claude request: model="minimax:default/MiniMax-M2.7"
    ↓
ProxyServer receives at /v1/chat/completions
    ↓
ModelRouter.route("minimax:default/MiniMax-M2.7")
    ↓
Returns (miniMaxDefaultAccount, "MiniMax-M2.7")
    ↓
Proxy forwards to miniMaxDefaultAccount.endpoint/v1/chat/completions
    ↓
Upstream response streamed back
```

---

## 11. Implementation Recommendations

### Phase 1: Core Infrastructure

1. **Account Model**
   ```swift
   struct Account: Codable, Identifiable {
       let id: UUID
       var label: String
       var provider: ProviderType
       var apiKeyRef: String  // Keychain reference
       var customEndpoint: String?
       var apiFormat: APIFormat
       var defaultModel: String?
       var isCurrent: Bool
       var meta: AccountMeta?
   }
   ```

2. **AccountStore**
   ```swift
   @Observable
   class AccountStore {
       var accounts: [Account] = []
       var proxySettings: ProxySettings

       func currentAccount(for provider: ProviderType) -> Account?
       func switchAccount(_ account: Account) async throws
   }
   ```

3. **Model Router**
   - Implement `route(model: String) -> (Account, String)?`
   - Support format: `provider:label/model`

### Phase 2: Proxy Integration

1. **ProxyService Enhancement**
   - Add `setActiveAccount()` for hot-switch
   - Track current account per provider type
   - Parse model name for routing

2. **Request Handling**
   - Extract model from request
   - Route to appropriate account
   - Forward request with correct credentials

### Phase 3: UI

1. **StatusPopover**
   - Show proxy status
   - Group accounts by provider
   - Checkmark current account
   - Refresh button

2. **Settings Window**
   - Accounts tab: list + add + delete
   - Proxy tab: port + admin key + status

3. **Tray Menu**
   - Per-provider submenus
   - Account switching
   - Usage display

### Phase 4: Usage Tracking

1. **Quota Polling**
   - Per-account polling interval
   - Parse response with QuotaCheck protocol
   - Update UI with usage bars

2. **Token Counting**
   - Already implemented per PROGRESS.md
   - Ensure SSE streaming passthrough

### Key Differences from CC-Switch

| Feature | CC-Switch | CoderSwitch | Implication |
|---------|-----------|-------------|-------------|
| Multi-tool | 5 CLI tools | 2 (Claude, Codex) | Simpler scope |
| Config files | Writes to each CLI | Uses proxy | No hot-config |
| Hot-switch | Proxy takeover | Already proxy-based | Built-in |
| MCP | Yes | No | Skip MCP sync |
| Failover | Queue + circuit breaker | Per-account | Different model |
| Additive mode | OpenCode/OpenClaw | Not needed | Simpler |

### Recommended Implementation Order

1. **Account Model + Store** - Foundation
2. **Model Router** - Core routing logic
3. **Proxy Integration** - Request handling
4. **StatusPopover** - Basic UI
5. **Tray Menu** - Quick switching
6. **Quota Polling** - Usage visibility
7. **Provider Presets** - Easy setup

### Files to Reference

| CC-Switch File | Purpose |
|----------------|---------|
| `src-tauri/src/services/provider/mod.rs` | Main switch logic |
| `src-tauri/src/provider.rs` | Provider data model |
| `src-tauri/src/tray.rs` | System tray |
| `src-tauri/src/services/proxy.rs` | Proxy service |
| `src/types.ts` | Frontend types |
| `src/hooks/useProviderActions.ts` | Switch hook |
| `src/config/claudeProviderPresets.ts` | Preset structure |

---

## Appendix: CC-Switch GitHub

- **Repository**: https://github.com/farion1231/cc-switch
- **Website**: https://ccswitch.io
- **License**: MIT

## Appendix: Quick Reference

### ProviderCategory Values

```typescript
type ProviderCategory =
  | "official"       // Direct official API
  | "cn_official"     // Chinese cloud official
  | "cloud_provider" // AWS Bedrock, etc.
  | "aggregator"      // API aggregator websites
  | "third_party"     // Third-party suppliers
  | "custom"         // User-defined
  | "omo"            // Oh My OpenCode
  | "omo-slim";      // Oh My OpenCode Slim
```

### APIFormat Values

```typescript
type APIFormat =
  | "anthropic"         // Native Anthropic Messages API
  | "openai_chat"       // OpenAI Chat Completions (needs conversion)
  | "openai_responses"  // OpenAI Responses API (needs conversion)
  | "gemini_native";    // Gemini Native (needs conversion)
```

### App Config Locations

```bash
~/.claude/settings.json           # Claude Code
~/.config/hairstyle/config.toml  # Codex
~/.gemini-cli/config.json        # Gemini CLI
~/.config/opencode/opencode.json # OpenCode
~/.openclaw/openclaw.json        # OpenClaw
```