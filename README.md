# CoderSwitch

A local macOS menu bar app for managing AI subscriptions and API keys across multiple providers. Provides a single OpenAI- and Anthropic-compatible proxy endpoint for Claude Code and Codex.

## Features

- **Multi-provider support**: OpenAI, Anthropic, OpenRouter, MiniMax, and custom OpenAI/Anthropic-compatible endpoints
- **Multiple accounts per provider**: Easily switch between different API keys and endpoints
- **Claude Code quick switch**: Point Claude Code at any Anthropic-compatible account from the menu bar
- **Local proxy**: Single proxy URL for Claude Code (`ANTHROPIC_BASE_URL`) and OpenAI-compatible clients (`OPENAI_BASE_URL`)
- **Responses API support**: Proxies OpenAI-compatible `/v1/responses` calls as well as chat completions
- **Usage tracking**: Tracks token usage (input, output, cache) by day/week/month/year
- **Request logs**: Shows recent proxy requests with status, latency, route, and token counts
- **Quota monitoring**: Polls provider APIs for balance and request limits
- **Secure storage**: API keys and OAuth tokens encrypted in local SQLite storage
- **Menu bar app**: Runs silently in the menu bar, no Dock icon

## Requirements

- macOS 14.0 (Sonoma) or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Setup

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode and run
open CoderSwitch.xcodeproj
```

Or build from command line:

```bash
xcodebuild -scheme CoderSwitch -configuration Debug build
```

## Configuration

### Adding Accounts

1. Click the CoderSwitch menu bar icon
2. Click "Settings..."
3. In the Accounts tab, click "+"
4. Select your provider and enter your API key

### OAuth Accounts For CLIProxyAPI

The OAuth tab can connect Codex and Gemini accounts using the same OAuth client
settings used by CLIProxyAPI. After authentication, CoderSwitch writes
CLIProxyAPI-compatible credential files into:

```bash
~/.cli-proxy-api
```

Use the "Install" button on an existing OAuth account to refresh and rewrite its
CLIProxyAPI auth file. This path avoids overwriting `~/.codex/auth.json` or
`~/.gemini/.env`, so the old native-CLI auth method remains untouched.

Codex OAuth accounts are currently used for import/export and quota visibility.
They are not routed through CoderSwitch's local proxy; proxy routing is for
API-key OpenAI-compatible and Anthropic-compatible accounts.

You can also import existing Codex `auth.json` files from the OAuth tab's add
menu. CoderSwitch imports the ChatGPT OAuth tokens, email, and account id, and
updates an existing Codex account when the imported file matches by email or
account id.

CoderSwitch does not commit a Google OAuth client secret. If you test a Google
OAuth client that still requires one, provide it locally with
`CODERSWITCH_GOOGLE_OAUTH_CLIENT_SECRET` or the
`CoderSwitchGoogleOAuthClientSecret` Info.plist key.

### Provider Routing

When using the proxy, specify models using the provider's routing slug:

| Provider | API shape | Routing format | Example |
|----------|-----------|----------------|---------|
| OpenAI | OpenAI-compatible | `openai-direct:label/model` | `openai-direct:work/gpt-4o` |
| Anthropic | Anthropic-compatible | `anthropic-direct:label/model` | `anthropic-direct:work/claude-sonnet-4` |
| OpenRouter | OpenAI-compatible | `openrouter:label/model` | `openrouter:default/anthropic/claude-3-opus` |
| MiniMax | OpenAI-compatible | `minimax:label/model` | `minimax:default/MiniMax-M2.7` |
| OpenAI-compatible (custom) | OpenAI-compatible | `openai:label/model` | `openai:work/gpt-4o` |
| Anthropic-compatible (custom) | Anthropic-compatible | `anthropic:label/model` | `anthropic:work/claude-sonnet-4` |

You can also use the account alias as the model name to use the account's default model.
For example, if an Anthropic-compatible custom account is labeled `work` and has
`claude-sonnet-4` selected as its default model, `anthropic:work` routes to that
model automatically.

OpenAI-compatible providers are used for `/v1/chat/completions`,
`/v1/responses`, and other OpenAI-style `/v1/*` requests. Anthropic-compatible
providers are used for `/v1/messages`, which is the path Claude Code uses.
Chinese proxy services and other gateway providers should be added as either
`OpenAI-compatible (custom)` or `Anthropic-compatible (custom)`, depending on
which API shape their endpoint exposes.

Google Antigravity and Codex OAuth accounts are managed for account switching
and visibility, but they are not routed through the local API proxy.

### Claude Code

Claude Code can use CoderSwitch through the local Anthropic-compatible proxy.
Add an `Anthropic` or `Anthropic-compatible (custom)` account, set its API key,
and optionally choose a default model in Settings. CoderSwitch uses that default
model when Claude Code asks for a generic Sonnet/Haiku/Opus model.

The easiest path is the menu bar:

1. Open CoderSwitch from the menu bar.
2. Expand **Quick Switch**.
3. Under **Claude Code**, click the Anthropic-compatible account to use.
4. To go back to normal Claude Code login, click **Official Claude**.

Quick Switch updates `~/.claude/settings.json` while preserving unrelated
settings. It writes:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8484",
    "ANTHROPIC_AUTH_TOKEN": "<admin-key>:<account-id>",
    "API_TIMEOUT_MS": "600000"
  }
}
```

When the selected account has a default model, CoderSwitch also writes
`ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, and `ANTHROPIC_DEFAULT_OPUS_MODEL` to that
model. Switching to **Official Claude** removes only the CoderSwitch-managed env
keys.

You can also launch Claude Code directly from Settings > Accounts with
**Open Claude Code** on an Anthropic-compatible account. That starts the proxy if
needed, asks for a project folder, writes the same Claude Code settings, and
opens Terminal with Claude Code pointed at CoderSwitch for that account.

Manual setup works too:

```bash
export ANTHROPIC_BASE_URL=http://localhost:8484
export ANTHROPIC_AUTH_TOKEN='<admin-key>'
claude
```

Use `<admin-key>:<account-id>` instead of just `<admin-key>` to pin Claude Code
to one account. The account id is visible in exported CoderSwitch config files;
the menu bar quick switch handles this automatically.

### Environment Variables

**Claude Code:**
```bash
export ANTHROPIC_BASE_URL=http://localhost:8484
export ANTHROPIC_AUTH_TOKEN='<admin-key>'
```

**Codex / OpenAI clients:**
```bash
export OPENAI_BASE_URL=http://localhost:8484/v1
export OPENAI_API_KEY='<admin-key>'
```

### Admin Key

The proxy requires authentication using the admin key shown in Settings > Proxy. Send it as:
- `Authorization: Bearer <admin_key>` for OpenAI-compatible requests
- `x-api-key: <admin_key>` for Anthropic-compatible requests

## Architecture

```
┌──────────────────────────────────────────┐
│  Menu Bar App (SwiftUI)                  │
│  ┌────────────────────────────────────┐  │
│  │ StatusPopover                      │  │
│  │  ▸ Proxy: running :8484 █        │  │
│  │  ▸ OpenRouter                      │  │
│  │    or: Credits 3/10 ████░░        │  │
│  │  [Refresh] Settings Quit          │  │
│  └────────────────────────────────────┘  │
└──────────────────┬───────────────────────┘
                   │
┌──────────────────▼───────────────────────┐
│  ProxyServer (Hummingbird :8484)          │
│  Auth: Bearer <adminKey>                  │
│  /v1/chat/completions → upstream (OpenAI) │
│  /v1/responses        → upstream (OpenAI) │
│  /v1/messages         → upstream (Anthropic) │
└───────────────────────────────────────────┘
```

## Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI** for the UI
- **Hummingbird 2.x** for the HTTP proxy server
- **GRDB/SQLite + CryptoKit** for local credential storage
- **XcodeGen** for project generation

## Security

See [SECURITY.md](SECURITY.md) for reporting instructions, secret-handling
notes, and known hardening items.

## License

MIT. See [LICENSE](LICENSE).
