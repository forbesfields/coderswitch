# CoderSwitch

A local macOS menu bar app for managing AI subscriptions and API keys across multiple providers. Provides a single OpenAI- and Anthropic-compatible proxy endpoint for Claude Code and Codex.

## Features

- **Multi-provider support**: OpenRouter, MiniMax, and custom OpenAI/Anthropic-compatible endpoints
- **Multiple accounts per provider**: Easily switch between different API keys and endpoints
- **Local proxy**: Single proxy URL for Claude Code (`ANTHROPIC_BASE_URL`) and Codex/OpenAI (`OPENAI_BASE_URL`)
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

| Provider | Routing Format | Example |
|----------|---------------|---------|
| OpenRouter | `openrouter:label/model` | `openrouter:default/anthropic/claude-3-opus` |
| MiniMax | `minimax:label/MiniMax-M2.7` | `minimax:default/MiniMax-M2.7` |
| Custom | `provider:label/model` | `openai-compatible:work/gpt-4o` |

You can also use the account alias as the model name to use the account's default model.

### Environment Variables

**Claude Code:**
```bash
export ANTHROPIC_BASE_URL=http://localhost:8484
```

**Codex / OpenAI clients:**
```bash
export OPENAI_BASE_URL=http://localhost:8484/v1
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
