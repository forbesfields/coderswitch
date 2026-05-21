# CoderSwitch Manual Test Checklist

Run these checks before tagging a release. Use test keys/accounts where possible.

## Fresh Launch

- [ ] Run `xcodegen generate`.
- [ ] Run `xcodebuild -scheme CoderSwitch -configuration Debug build`.
- [ ] Launch `CoderSwitch.app` from Xcode or DerivedData.
- [ ] Confirm the app appears only in the menu bar and opens the Settings window.
- [ ] Open Settings > Proxy and confirm the setup checklist shows expected local config files.
- [ ] Confirm the proxy auto-starts if "Start proxy when app launches" is enabled.

## Account Setup

- [ ] Add an OpenRouter API-key account.
- [ ] Add a MiniMax API-key account.
- [ ] Add one custom OpenAI-compatible endpoint.
- [ ] Add one custom Anthropic-compatible endpoint if available.
- [ ] Rename an account and confirm the new nickname persists after app restart.
- [ ] Disable an account and confirm it is dimmed, marked disabled, and not used for routing.
- [ ] Re-enable the account and confirm routing resumes.
- [ ] Click "Test provider connection" for each API-key account and confirm success or a clear error.
- [ ] Click "Fetch models" and select a default model.

## OAuth Accounts

- [ ] Import an existing Codex `auth.json`.
- [ ] Confirm the imported Codex account appears in OAuth and Accounts.
- [ ] Re-import the same file and confirm it updates instead of duplicating.
- [ ] Use Install/Switch for a Codex account and confirm `~/.codex/auth.json.coderswitch.bak` is created when an existing file is overwritten.
- [ ] Confirm failed writes restore the prior config file if you simulate an unwritable target.
- [ ] If using CLIProxyAPI, confirm files are written under `~/.cli-proxy-api`.

## Proxy Endpoints

- [ ] Copy the admin key from Settings > Proxy.
- [ ] Run `curl http://localhost:8484/healthz` and confirm `{"ok":true}`.
- [ ] Run `curl -H "Authorization: Bearer <admin_key>" http://localhost:8484/v1/models` and confirm local route IDs appear.
- [ ] Send a non-streaming OpenAI-compatible `/v1/chat/completions` request through `http://localhost:8484/v1`.
- [ ] Send a streaming OpenAI-compatible `/v1/chat/completions` request and confirm chunks arrive incrementally.
- [ ] Send a `/v1/responses` request through `http://localhost:8484/v1`.
- [ ] Send an Anthropic-compatible `/v1/messages` request through `http://localhost:8484`.
- [ ] Send `/v1/messages/count_tokens` if the upstream supports it.
- [ ] Use `Authorization: Bearer <admin_key>:<account_uuid>` or `x-api-key: <admin_key>:<account_uuid>` and confirm routing is scoped to that account.

## Usage And Logs

- [ ] Open Settings > Usage and confirm request/token totals update after successful proxy calls.
- [ ] Confirm Responses API usage appears in totals for both non-streaming and streaming responses.
- [ ] Open Settings > Proxy and confirm Recent Requests shows method, path, status, latency, route, and token count.
- [ ] Trigger an upstream error and confirm it appears in Recent Requests.
- [ ] Click Clear in Recent Requests and confirm logs are removed from the UI.
- [ ] Restart the app and confirm recent logs reload from SQLite.

## Quotas And Warnings

- [ ] Click Refresh in the menu bar popover and confirm OpenRouter quota/balance updates.
- [ ] Confirm MiniMax request windows display consumed request counts correctly.
- [ ] Confirm providers without a quota endpoint show a graceful "No quota endpoint" state.
- [ ] Enable a circuit breaker warning, trigger enough failures, and confirm the warning appears without blocking routing.

## Release Readiness

- [ ] Run `xcodebuild -scheme CoderSwitch -configuration Debug test`.
- [ ] Run `xcodebuild -scheme CoderSwitch -configuration Release build`.
- [ ] Run `bash scripts/package_release.sh` to create `build/release/CoderSwitch.dmg`.
- [ ] Confirm the app icon, About window version, and README screenshots are release-ready.
- [ ] Set `DEVELOPER_ID_APPLICATION` and `NOTARYTOOL_PROFILE`, rerun the package script, and confirm notarization/stapling succeeds.
- [ ] Verify the DMG launches on a clean macOS user account.
