# CoderSwitch OSS Release Plan

## Context

CoderSwitch is a macOS menu bar app that acts as a local multi-provider AI proxy (OpenAI/Anthropic-compatible), routing requests through configured accounts. The user wants to ship it as open source on GitHub. This plan catalogs everything missing or needing attention before that can happen.

---

## What's Already Done

- Feature-complete app with SwiftUI UI, Hummingbird proxy, GRDB SQLite storage
- OAuth flows (Codex + Google Gemini) with PKCE
- Token encryption via AES-GCM SecretBox (master key on disk)
- Constant-time admin key comparison
- Comprehensive test suite (3 test files, 20 tests)
- XcodeGen project setup
- README.md with architecture docs
- Menu bar icon + app icon assets

---

## Critical Blockers for OSS

### 1. LICENSE file
**Done:** Added `LICENSE` with the MIT license text and f9Labs copyright.

### 2. No CI/CD
**Action:** Add GitHub Actions workflow.
- Run tests on every PR and push to main
- Build verification (no need for full notarization on PRs)
- Suggested: `test.yml` (Swift test on macOS 14+), `build.yml` (xcodebuild verify)

---

## Security Issues Requiring Attention

### 3. Google OAuth Client Secret Must Not Be Committed
`OAuthProvider.swift` should not contain a real Google OAuth client secret. It now reads an optional local value from `CODERSWITCH_GOOGLE_OAUTH_CLIENT_SECRET` or the `CoderSwitchGoogleOAuthClientSecret` Info.plist key.

**Recommendation:** Rotate any previously committed Google OAuth client secret before publishing, and prefer an installed-app PKCE OAuth client that does not require a confidential client secret.

### 4. Admin Key Stored Unencrypted in SQLite
The `proxy_settings.admin_key` column stores the admin key in plaintext. Anyone with file access to `~/Library/Application Support/CoderSwitch/coderswitch.sqlite` can extract the proxy admin key.
**Recommendation:** Document this in SECURITY.md. It's a known trade-off — not unusual for local-proxy apps.

### 5. CLI Proxy Auth Files Written in Plaintext
`~/.cli-proxy-api/*.json` contains access/refresh tokens in plaintext (0600 perms). This is the same trade-off other CLI proxy tools make.
**Recommendation:** Document in SECURITY.md.

### 6. OAuthStore Imports Tokens from External Files
On init, `OAuthStore` imports from `~/.codex/auth.json` — tokens from external tools get imported into CoderSwitch's database.
**Security note:** This means deleting a CoderSwitch account doesn't invalidate the original auth file — tokens remain valid externally. Worth noting in docs.

### 7. AboutView Says "Keychain" But Uses SecretBox
`AboutView.swift` feature list states "Secure API key storage in Keychain" — but the app uses `SecretBox` (master key on filesystem), not Keychain.
**Action:** Fix the copy in `AboutView.swift`.

### 8. ClaudeCodeLauncher Env Var Exposure
`AccountsTab.swift` creates a temp shell script containing `ANTHROPIC_AUTH_TOKEN` env var (the admin key), launches via `osascript/Terminal`, then deletes the script.
**Risk:** Brief window where the admin key could be observed via `ps` or `/proc`. Low risk but worth noting.
**Recommendation:** Document in SECURITY.md as a known trade-off of the Claude Code launcher feature.

---

## Missing Supporting Files

### 9. CHANGELOG.md
Track versions. Currently at 0.1.0 (build 1).
**Action:** Create initial CHANGELOG.md.

### 10. CONTRIBUTING.md
**Action:** Add `CONTRIBUTING.md` with:
- How to set up dev environment (`xcodegen generate && xcodebuild`)
- Code style (Swift 6 strict concurrency)
- How to run tests
- PR process

### 11. CODE_OF_CONDUCT.md
**Action:** Add `CODE_OF_CONDUCT.md` (consider adopting Contributor Covenant or similar).

### 12. GitHub PR/Issue Templates
**Action:** Add `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE.md`.

### 13. .github/ folder with workflows
At minimum: test workflow, potentially a build verification workflow.

---

## Code Quality / Documentation Fixes

### 14. Hardcoded User Agent in QuotaPoller
`QuotaPoller.swift` has hardcoded `"antigravity/2.0.1 darwin/arm64"`. Version could drift.
**Action:** Derive version from `Bundle.main.infoDictionary` at runtime.

### 15. QuotaPoller Project ID Fetch Has No Backoff
`fetchGoogleAntigravityProjectId()` retries two fixed endpoints with no timeout/backoff — could hammer endpoints.
**Action:** Add basic retry with delay.

### 16. OAuthCallbackHandler Is a Stub
Returns `false` — class is dead code.
**Action:** Remove it or document why it exists.

### 17. OAuthStore.writeConfigFile() Backup Logic Is Complex
Hard to reason about. Not a blocker but worth a code review note.

### 18. Constant-Time Comparison Leaks Length
`ProxyServer.swift` early-returns if `aBytes.count != bBytes.count` before constant-time comparison — this leaks length info via timing.
**Action:** Use `CryptoKit` `isEqual` on `SymmetricKey` or a proper constant-time compare that doesn't early-return on length mismatch.

---

## Priority Order

1. Add LICENSE (critical blocker)
2. Add GitHub Actions CI (critical for OSS quality)
3. Add GitHub templates (PR + issue)
4. Write SECURITY.md documenting the security trade-offs
5. Fix AboutView "Keychain" copy
6. Add CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md
7. Fix constant-time comparison length leak
8. Address code quality issues (user agent, backoff, dead code)

---

## Verification

After making changes:
1. Run `xcodegen generate` to regenerate project
2. Run `xcodebuild -scheme CoderSwitch -configuration Debug test` to verify tests pass
3. Launch the app and verify: menu bar icon appears, proxy starts on 127.0.0.1:8484, OAuth flow completes, accounts are persisted
4. Verify no new warnings from Swift compiler (Swift 6 strict concurrency mode)
5. Review all modified files for any remaining hardcoded secrets or security issues
