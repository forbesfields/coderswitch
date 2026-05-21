# CC-Switch Findings for CoderSwitch

This document tracks how CC-Switch implements profile/API key switching between Claude Code and Codex, and how to implement similar functionality in CoderSwitch.

## Overview

CC-Switch is a Tauri 2 + React + Rust desktop app that manages API configurations for Claude Code, Codex, Gemini CLI, OpenCode, and OpenClaw. It provides one-click switching between different API providers/endpoints.

---

## 1. Architecture

### Stack
- **Frontend**: React 18 + TypeScript + Vite + TailwindCSS + TanStack Query
- **Backend**: Tauri 2 (Rust) with SQLite database
- **Storage**: `~/.cc-switch/cc-switch.db` (SQLite) + JSON config files

### Key Components

```
Frontend (React)
├── components/providers/   # Provider UI (cards, list, dialogs)
├── hooks/useProviderActions.ts  # Business logic for switching
├── lib/query/mutations.ts # React Query mutations
└── lib/api/providers.ts   # Tauri IPC wrapper

Backend (Rust/Tauri)
├── commands/provider.rs   # Tauri command handlers
├── services/provider/     # ProviderService (switch logic)
├── database/              # SQLite DAO layer
└── live.rs                # Live config file operations
```

---

## 2. Data Model

### Provider Structure

Providers are stored in SQLite with this key structure (from `src-tauri/src/provider.rs`):

```rust
pub struct Provider {
    pub id: String,
    pub label: String,
    pub category: String,           // "official", "third_party", "omo", etc.
    pub settings_config: serde_json::Map<String, serde_json::Value>, // Contains env vars
    pub is_current: bool,
    pub meta: Option<ProviderMeta>,
}

pub struct ProviderMeta {
    pub provider_type: Option<String>,  // e.g., "github_copilot"
    pub api_format: Option<String>,     // "openai_chat", "openai_responses"
    pub is_full_url: bool,
    pub claude_desktop_mode: Option<ClaudeDesktopMode>,
}
```

### AppType Enum

Each CLI tool is identified by an `AppType`:
- `Claude` - Claude Code
- `Codex` - Codex
- `Gemini` - Gemini CLI
- `OpenCode` - OpenCode
- `OpenClaw` - OpenClaw
- `Hermes` - Hermes Agent
- `ClaudeDesktop` - Claude Desktop

---

## 3. How Switching Works

### Flow

1. **Frontend**: User clicks "switch" on a provider card
2. `useSwitchProviderMutation` is called with provider ID and appId
3. Tauri command `switch_provider` is invoked via IPC
4. Backend `ProviderService::switch()` handles the actual logic
5. On success, React Query cache is invalidated and tray menu updated

### Key Switch Logic (from `services/provider/mod.rs`)

```rust
pub fn switch(state: &AppState, app_type: AppType, id: &str) -> Result<SwitchResult, AppError> {
    // 1. Validate provider exists
    let providers = state.db.get_all_providers(app_type.as_str())?;
    let provider = providers.get(id).ok_or_else(|| ...)?;

    // 2. Check proxy takeover mode (hot-switch vs normal)
    let is_proxy_running = futures::executor::block_on(state.proxy_service.is_running());
    let should_hot_switch = is_taken_over && is_proxy_running;

    if should_hot_switch {
        // HOT SWITCH: Only update proxy target, no Live config write
        state.proxy_service.hot_switch_provider(app_type.as_str(), id)?;
        return Ok(SwitchResult::default());
    }

    // NORMAL SWITCH:
    // 1. Backfill current live config to current provider in DB
    // 2. Update local settings current_provider
    // 3. Update database is_current flag
    // 4. Write target provider config to live files
    // 5. Sync MCP configuration
    Self::switch_normal(state, app_type, id, &providers)
}
```

### Two Switching Modes

1. **Hot Switch (Proxy Takeover Mode)**:
   - When proxy is running and takeover is enabled
   - Only updates the proxy's target provider
   - No live config file is written
   - Works without restarting the CLI

2. **Normal Switch**:
   - Updates database (`is_current` flag)
   - Writes provider config to live config file
   - Syncs MCP configuration
   - May require CLI restart for changes to take effect

---

## 4. Live Config Files

CC-Switch writes configuration to each tool's native config location:

| App | Config Location |
|-----|-----------------|
| Claude Code | `~/.claude/settings.json` (or symlink swap for hot-switch) |
| Codex | `~/.codex/config.json` |
| Gemini | `~/.gemini-cli/config.json` |

### Config Writing Pattern

```rust
fn write_live_with_common_config(
    db: &Database,
    app_type: &AppType,
    provider: &Provider,
) -> Result<(), AppError> {
    // 1. Read existing live config
    // 2. Merge provider config (env vars, api format, etc.)
    // 3. Handle common config snippet preservation
    // 4. Atomic write (temp file + rename)
}
```

---

## 5. Proxy Service (Local Proxy)

CC-Switch runs a local proxy server that:
- Routes requests to different upstream providers
- Performs format conversion (OpenAI → Anthropic)
- Supports hot-switching without CLI restart
- Handles failover automatically

The proxy is optional - switching can work directly by writing to live config files.

---

## 6. System Tray Integration

CC-Switch updates the system tray menu when switching:
- Shows current active provider per app
- Quick-switch directly from tray
- Uses `tauri::command::update_tray_menu`

---

## 7. Key Implementation Details for CoderSwitch

### What CoderSwitch Has

From `FROM_CODERSWITCH/PROGRESS.md`:
- Swift 6 menu bar app with SwiftUI
- Hummingbird 2.x HTTP proxy server on port 8484
- Account store with JSON + Keychain
- Provider routing: `minimax/MiniMax-M2.7`, `openrouter:work/...`
- Quota polling per account
- Token usage tracking

### What CoderSwitch Needs for Profile Switching

To implement CC-Switch-like profile switching:

1. **Database Schema**:
   ```swift
   struct Account: Codable {
       let id: UUID
       var label: String
       var provider: ProviderType  // enum: openRouter, miniMax, etc.
       var apiKey: String           // stored in Keychain
       var customEndpoint: String?
       var isCurrent: Bool
   }
   ```

2. **Provider Service**:
   - `switch(accountId:)` - sets `isCurrent` on account, clears on others
   - Writes active account config to a config file or proxy
   - Updates tray/status bar

3. **Config File Location**:
   - For Claude Code: `~/.claude/settings.json` env vars
   - For Codex: similar location
   - Or use the local proxy as single endpoint

4. **Hot-Switch via Proxy**:
   - When using local proxy, switching updates proxy target
   - No need to restart CLI or rewrite config files
   - Proxy routes to the correct upstream based on model name

5. **Tray/Status Bar**:
   - Show current account per provider
   - Click to switch
   - Show quota status

---

## 8. Key Files to Reference

| File | Purpose |
|------|---------|
| `src-tauri/src/services/provider/mod.rs` | Main switch logic (~1400 lines) |
| `src-tauri/src/commands/provider.rs` | Tauri command handlers |
| `src-tauri/src/claude_desktop_config.rs` | Claude config file handling |
| `src-tauri/src/tray.rs` | System tray menu |
| `src/hooks/useProviderActions.ts` | Frontend switch hook |
| `src/lib/api/providers.ts` | API layer |

---

## 9. Differences from CC-Switch

| Aspect | CC-Switch | CoderSwitch |
|--------|----------|-------------|
| Platform | Tauri (Windows/Mac/Linux) | Swift menu bar (macOS only) |
| Config | Writes to each CLI's config file | Uses local proxy + single endpoint |
| Hot-switch | Proxy takeover mode | Already proxy-based (simpler) |
| Multi-tool | 5 CLI tools | Focus on Claude Code + Codex |
| Accounts | Per-provider with categories | Per-provider with API keys |

---

## 10. Recommendations for CoderSwitch

1. **Use the proxy for switching**: Since CoderSwitch already runs a proxy, switching accounts can simply update the proxy's target account - no config file writes needed.

2. **Store `isCurrent` flag per account**: Add an `isCurrent: Bool` field to Account and a `currentAccountId` per provider type.

3. **Tray menu with accounts**: Show all accounts grouped by provider, checkmark the current one.

4. **Model routing**: Use CC-Switch's model slug pattern (`provider:label/model`) to route requests through the proxy.

5. **Persistence**: When switching via proxy, only update in-memory state + database. No need to touch Claude config files.