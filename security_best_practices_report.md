# CoderSwitch Security Audit

Date: 2026-05-20

## Executive Summary

CoderSwitch is a local macOS Swift app that stores high-value API keys and OAuth refresh tokens, runs a localhost proxy, imports and exports CLI auth files, and forwards authenticated traffic to AI providers. The proxy itself has several good baseline controls: it binds to `127.0.0.1`, requires a generated admin key for protected API routes, uses constant-time comparison for the admin key, uses parameterized SQL through GRDB, and caps proxied request body collection at 16 MiB.

The biggest security problem is secret-at-rest protection. API keys and OAuth tokens are encrypted in SQLite, but the AES master key is stored as a normal file beside the database. Any local process or backup with access to the Application Support directory can decrypt the database without needing Keychain or user presence. This should be fixed before treating the app as safe for real long-lived credentials.

I also found missing OAuth `state` validation, an unrestricted OAuth callback listener, broad App Transport Security settings, unsandboxed app entitlements, unvalidated custom upstream endpoints, and a checked-in Google OAuth client secret. Some of these are acceptable during early local development, but they should be narrowed before distribution or daily use with real accounts.

## Scope and Method

- Reviewed Swift app, proxy, persistence, OAuth, settings, UI input, and project configuration under `/Users/forbes/Programming/coderswitch`.
- Searched for secret-like literals and credential handling paths.
- Reviewed dependency pins in SwiftPM `Package.resolved`.
- Ran `plutil -lint` on app plist and entitlements.
- Ran `xcodebuild -scheme CoderSwitch -configuration Debug test`.
- Checked current public web advisory surfaces for SwiftNIO/Hummingbird/GRDB-related dependency concerns at a high level.

## Critical Findings

### C-1. Database encryption key is stored next to the encrypted secrets

Evidence:

- `CoderSwitch/Database/SecretBox.swift:4-6` states the master key lives at `~/Library/Application Support/CoderSwitch/.master.key`.
- `CoderSwitch/Database/SecretBox.swift:9-25` creates or reads that file directly and uses it as the AES-GCM key.
- `CoderSwitch/Database/Database.swift:14-18` stores `coderswitch.sqlite` in the same Application Support directory.
- `CoderSwitch/Stores/AccountStore.swift:283-286` encrypts API keys into `accounts.api_key_encrypted`.
- `CoderSwitch/Stores/OAuthStore.swift:543-545` encrypts OAuth access, refresh, and ID tokens with `SecretBox`.

Impact: A local malware process, another user process with file access, or an unencrypted backup that gets both files can decrypt every stored API key and OAuth refresh token.

Why this matters:

AES-GCM is fine, but the key storage model collapses the protection boundary. The `.master.key` file is effectively the database password. File mode `0600` helps against other macOS users, but it does not protect against same-user compromise, app support folder sync/backup exposure, or accidental exfiltration of the whole app data directory.

Recommended fix:

- Store the master key in macOS Keychain, ideally with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Keep SQLite encryption only as envelope encryption: Keychain protects the root key, `SecretBox` protects database blobs.
- Add a migration path:
  - If `.master.key` exists, read it once.
  - Store it into Keychain under a new account name.
  - Verify decryption still works.
  - Delete `.master.key` after successful migration.
- Consider rotating the master key after migration if any real credentials have already been stored.

### C-2. OAuth callback accepts authorization codes without `state` validation

Evidence:

- `CoderSwitch/Stores/OAuthStore.swift:119-130` constructs the OAuth authorization URL with PKCE, but no `state` parameter.
- `CoderSwitch/Stores/OAuthStore.swift:295-307` extracts `code` and immediately completes the callback flow.
- `CoderSwitch/Stores/OAuthStore.swift:331-339` accepts any `GET` path and builds a callback URL from it.

Impact: A local or browser-origin attacker may be able to inject an authorization code into the waiting callback flow, causing account confusion or linking the wrong account to CoderSwitch.

Why this matters:

PKCE protects the code exchange from interception, but `state` protects the app from callback mix-up and CSRF-style login injection. Native app OAuth flows should use both.

Recommended fix:

- Generate a cryptographically random `state` value at the same time as `PKCEChallenge`.
- Include it in the authorization request.
- Store it for the pending flow.
- Require the callback `state` to exactly match before accepting `code`.
- Clear it on success, failure, and cancel.

## High Findings

### H-1. OAuth callback listener may bind beyond loopback and does not verify callback path

Evidence:

- `CoderSwitch/Stores/OAuthStore.swift:260` starts `NWListener(using: .tcp, on: port)` without explicitly binding to `127.0.0.1` or `::1`.
- `CoderSwitch/Stores/OAuthStore.swift:331-339` parses the first `GET` request path but does not check it equals the provider's expected callback path.
- `CoderSwitch/Models/OAuthProvider.swift:59-70` defines fixed callback paths and ports.

Risk:

The main proxy correctly binds to `127.0.0.1` in `CoderSwitch/Proxy/ProxyServer.swift:82-86`, but the OAuth callback server does not show the same explicit local-only binding. Depending on `NWListener` behavior and firewall state, this can expose the temporary callback receiver more broadly than intended. The callback parser also accepts any path carrying a `code`.

Recommended fix:

- Use `NWParameters` configured for local-only traffic where possible, or verify the connection endpoint is loopback before processing data.
- Reject callbacks whose path does not exactly match `provider.callbackPath`.
- Keep the listener lifetime as short as possible and stop it after first valid or invalid terminal callback.

### H-2. App Transport Security allows arbitrary loads globally

Evidence:

- `project.yml:44-45` sets `NSAllowsArbitraryLoads: true`.
- `CoderSwitch/Info.plist:27-30` contains the generated plist equivalent.
- `CoderSwitch/Views/AddAccountView.swift:65-72` saves custom endpoint text without URL scheme or host validation.
- `CoderSwitch/Proxy/ProxyServer.swift:413-419` builds upstream URLs from account endpoints without enforcing HTTPS.

Risk:

Global arbitrary loads allow non-TLS requests throughout the app. Combined with custom provider endpoints, users can accidentally send API keys, OAuth-adjacent traffic, and prompt contents over plaintext HTTP or to malformed endpoints.

Recommended fix:

- Remove global `NSAllowsArbitraryLoads`.
- Validate account endpoints before saving:
  - Require `https://` for all non-localhost endpoints.
  - Allow `http://127.0.0.1`, `http://localhost`, and `http://[::1]` only for explicit local development.
  - Reject URLs with embedded credentials.
- If a provider truly needs an ATS exception, add a narrow domain-specific exception rather than a global one.

### H-3. Persistent proxy admin key is stored in plaintext SQLite

Evidence:

- `CoderSwitch/Database/Database.swift:51-57` creates `proxy_settings.admin_key TEXT NOT NULL`.
- `CoderSwitch/Proxy/ProxySettings.swift:61-69` loads it directly.
- `CoderSwitch/Proxy/ProxySettings.swift:93-108` saves it directly.
- `CoderSwitch/Proxy/ProxyServer.swift:379-394` uses it to authenticate proxy requests.

Risk:

The main proxy binds to loopback, so this is not a network-exposed bearer token by default. Still, any local process or backup reader that gets the SQLite database can recover the admin key and use the proxy to spend upstream API credits from any configured key-backed account.

Recommended fix:

- Store the admin key in Keychain, or at minimum encrypt it with the same improved Keychain-backed `SecretBox`.
- Consider not persisting it at all unless the user asks for stability across launches.
- Regenerate on first run after migration if there is any chance the old SQLite database was copied around.

### H-4. Hardcoded Google OAuth client secret is committed

Evidence:

- `CoderSwitch/Models/OAuthProvider.swift:82-88` returns a literal `GOCSPX-...` client secret.
- `PLAN.md:42` also contains the same secret-like value.
- `CoderSwitch/Stores/OAuthStore.swift:223` and `CoderSwitch/Stores/OAuthStore.swift:486` send `client_secret` when present.
- `CoderSwitch/Stores/OAuthStore.swift:447` exports the Gemini client secret into CLIProxyAPI auth JSON.

Risk:

Native app OAuth client secrets cannot be kept secret once shipped, but committing them still creates operational risk. If this is a real Google OAuth client secret, it should be treated as exposed. It may be abused until Google restrictions or rotation limit it.

Recommended fix:

- Rotate the Google OAuth client secret in Google Cloud if this is a real client.
- Prefer an OAuth client type and flow that does not rely on a confidential client secret for a distributed desktop app.
- If a compatibility file requires the field, document that the value is a public/native-app client value rather than a secret, and minimize scopes.
- Remove the secret-like value from planning docs.

## Medium Findings

### M-1. App sandbox is disabled

Evidence:

- `project.yml:49` sets `com.apple.security.app-sandbox: false`.
- `CoderSwitch/CoderSwitch.entitlements:5-6` disables the sandbox.

Risk:

If the app is compromised, it has broader access to user files and local state than a sandboxed app. Since this app handles credentials and writes auth files, sandboxing may be inconvenient, but the current entitlement leaves no OS-level containment.

Recommended fix:

- Decide whether this app is for personal/dev-only use or distribution.
- For distribution, enable sandboxing and add only the specific file/network entitlements needed.
- If sandboxing is intentionally incompatible with writing `~/.codex` and `~/.cli-proxy-api`, document that threat model explicitly and keep release artifacts local/private.

### M-2. Request logs persist potentially sensitive metadata

Evidence:

- `CoderSwitch/Database/Database.swift:68-88` creates persistent request logs.
- `CoderSwitch/Stores/RequestLogStore.swift:54-99` stores path, account label, provider, model, upstream model, status, latency, usage, and error message.
- `CoderSwitch/Stores/RequestLogStore.swift:11-12` keeps 200 visible and 2,000 persisted logs.
- `CoderSwitch/Proxy/ProxyServer.swift:172-181` and other failure paths include the requested model in error messages.

Risk:

The logs do not appear to store request bodies or API keys, which is good. However, model names, account labels, routes, and upstream error messages can leak work context or account identity. If the SQLite database is copied, request history comes with it.

Recommended fix:

- Keep request body logging off by design.
- Consider encrypting request logs or making persistence opt-in.
- Add a retention setting such as "session only", "7 days", or "2,000 entries".
- Sanitize upstream error messages before persistence if providers may echo user input or sensitive identifiers.

### M-3. Upstream URL construction forwards arbitrary query strings

Evidence:

- `CoderSwitch/Proxy/ProxyServer.swift:413-419` concatenates the configured base URL, path, and raw query string into a URL.
- `CoderSwitch/Proxy/ProxyServer.swift:422-425` strips `/v1/` and passes through response subpaths.

Risk:

This is probably fine for trusted local clients, but it is not defensive against unusual path/query forms, embedded credentials in base URLs, or accidental double-query construction. Since credentials are attached as upstream headers, URL validation should be strict.

Recommended fix:

- Build upstream URLs with `URLComponents`.
- Reject base URLs containing username/password.
- Normalize path joining.
- Preserve only expected query parameters for pass-through endpoints if practical.

### M-4. Callback response HTML lacks basic hardening headers

Evidence:

- `CoderSwitch/Stores/OAuthStore.swift:310-323` returns a small success HTML page without `Cache-Control`, `X-Content-Type-Options`, or a restrictive `Content-Security-Policy`.

Risk:

The HTML is static and low-risk, but auth callbacks are sensitive. Hardening headers are cheap and prevent weird browser caching or content-sniffing behavior.

Recommended fix:

- Add `Cache-Control: no-store`.
- Add `X-Content-Type-Options: nosniff`.
- Add a restrictive `Content-Security-Policy`. If the close script remains, use a nonce or remove the script and show static text.

### M-5. No rate limiting or lockout on localhost proxy authentication

Evidence:

- `CoderSwitch/Proxy/ProxyServer.swift:379-394` checks the admin key but does not rate-limit failures.
- `CoderSwitch/Proxy/ProxySettings.swift:42-49` generates a strong 24-byte random key, which lowers brute-force feasibility.

Risk:

The key is strong enough that brute force is not a practical remote threat when bound to loopback, but local abuse and noisy probing are not surfaced or throttled.

Recommended fix:

- Track failed auth attempts in memory.
- Add a small per-process delay or temporary lockout after repeated failures.
- Optionally log aggregate auth failures without storing presented tokens.

## Low Findings and Positive Notes

### L-1. KeychainStore still uses broad default accessibility

Evidence:

- `CoderSwitch/Stores/KeychainStore.swift:10-28` stores generic passwords without `kSecAttrAccessible`.

Risk:

This code is now mainly used for legacy migration, but if revived, default Keychain accessibility may be broader than desired.

Recommended fix:

- If Keychain storage is reintroduced, set `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

### L-2. Project has hardened runtime enabled, but debug ad-hoc test run disables it

Evidence:

- `project.yml:58` enables hardened runtime.
- The test run output noted: `Disabling hardened runtime with ad-hoc codesigning`.

Risk:

This is normal for local debug signing, but release verification should check the final signed app rather than debug test artifacts.

Recommended fix:

- Add a release checklist step that verifies entitlements and hardened runtime on the final signed app with `codesign -dv --verbose=4`.

### L-3. Good baseline controls found

Evidence:

- Main proxy binds to loopback: `CoderSwitch/Proxy/ProxyServer.swift:82-86`.
- Protected proxy routes call `authorize`: for example `CoderSwitch/Proxy/ProxyServer.swift:98-99` and `CoderSwitch/Proxy/ProxyServer.swift:159-160`.
- Admin key comparison is constant-time for equal-length strings: `CoderSwitch/Proxy/ProxyServer.swift:379-394`.
- Request body collection is capped to 16 MiB for model requests: `CoderSwitch/Proxy/ProxyServer.swift:162`.
- API keys are not forwarded from clients; CoderSwitch injects stored upstream credentials: `CoderSwitch/Proxy/ProxyServer.swift:201-205`.
- SQL writes reviewed here use GRDB parameter binding rather than string interpolation.
- PKCE verifier/challenge uses `SecRandomCopyBytes` and SHA-256: `CoderSwitch/Models/PKCEChallenge.swift:8-20`.

## Dependency and Supply Chain Notes

- `Package.resolved` pins Hummingbird 2.23.0, GRDB 7.10.0, SwiftNIO 2.99.0, swift-nio-ssl 2.37.0, Swift Crypto 4.5.0, and related Swift server packages.
- I did not find a local SwiftPM audit tool in the repo.
- Public advisory checks did not turn up an obvious direct current advisory for the pinned top-level packages, but this should be automated in CI because advisory status changes over time.
- GitHub's advisory database supports Swift advisories, and SwiftNIO publishes a security process for supported 2.x versions. Use those as the ongoing monitoring sources.

Recommended fix:

- Add a dependency review step to CI or release checklist.
- Keep `Package.resolved` committed for reproducible builds.
- Regularly run `xcodebuild -resolvePackageDependencies` and review SwiftPM updates before release.

## Verification Results

Commands run:

```bash
plutil -lint CoderSwitch/Info.plist CoderSwitch/CoderSwitch.entitlements
xcodebuild -scheme CoderSwitch -configuration Debug test
```

Results:

- `plutil` passed for both files.
- `xcodebuild test` passed: 19 tests, 0 failures.

Limitations:

- This was a static/source audit plus existing test run, not a penetration test.
- I did not run a dynamic localhost attack harness, packet capture, or macOS sandbox release validation.
- I did not rotate or modify any secrets.
- I did not make code changes beyond writing this report.

## Recommended Fix Order

1. Move `SecretBox` root key into Keychain and migrate/delete `.master.key`.
2. Add OAuth `state` generation and validation.
3. Restrict OAuth callback listener/path handling.
4. Remove global ATS arbitrary loads and validate custom endpoints.
5. Move proxy admin key out of plaintext SQLite.
6. Rotate/remove the Google OAuth client secret if real.
7. Decide and document sandbox/distribution posture.
8. Add request-log privacy controls.
9. Add CI/release dependency advisory checks.
