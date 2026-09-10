# Security Policy

CoderSwitch is a local macOS menu bar app that stores AI provider credentials,
runs a loopback-only proxy, and can import or export credentials for local CLI
tools. Treat the app and its local data directory as sensitive.

## Supported Versions

CoderSwitch is pre-1.0 software. Security fixes are expected to land on the
latest `main` branch unless a tagged release states otherwise.

## Reporting a Vulnerability

Please do not open a public issue that contains API keys, OAuth tokens, local
database files, `.coderswitchconfig` exports, screenshots of credentials, or
other sensitive material.

If GitHub private vulnerability reporting is enabled for this repository, use
that first. If it is not enabled, contact the maintainer privately through
GitHub before publishing details. Include:

- A concise description of the issue.
- Steps to reproduce, preferably with test credentials or redacted examples.
- The affected commit or release.
- Any evidence of real credential exposure.

## Secret Handling

- Do not commit real API keys, OAuth tokens, `.env` files, signing identities,
  provisioning profiles, SQLite app data, `.master.key`, or
  `.coderswitchconfig` exports.
- API keys and OAuth tokens are encrypted in CoderSwitch's local SQLite
  database with CryptoKit `SecretBox`.
- The `SecretBox` root key is stored in the macOS Keychain
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Installations that still
  have a legacy `.master.key` file in `~/Library/Application Support/CoderSwitch/`
  migrate it into the Keychain on first launch; the file is deleted only after
  the Keychain write is verified.
- The proxy admin key is stored in the macOS Keychain, not in SQLite. It is
  imported from older plaintext databases on first launch, after which the
  database column is scrubbed.
- Config backup files (`*.coderswitchconfig`) contain decrypted API keys,
  OAuth tokens, proxy settings, and the proxy admin key. Keep them private and
  delete them when no longer needed.
- CLIProxyAPI-compatible auth files written under `~/.cli-proxy-api` contain
  OAuth credentials in plaintext files with local filesystem permissions. This
  is a local-tool interoperability tradeoff.
- Google OAuth client secrets should not be committed. If a Google OAuth client
  still requires a secret for local testing, provide it with
  `CODERSWITCH_GOOGLE_OAUTH_CLIENT_SECRET` or a local
  `CoderSwitchGoogleOAuthClientSecret` Info.plist value.

## Local Proxy Model

The proxy is designed for local use and binds to `127.0.0.1`. Protected proxy
routes require the generated admin key shown in Settings. Do not expose the
proxy port to a LAN, public interface, tunnel, reverse proxy, or container
network unless you have added your own access controls.

Use HTTPS custom provider endpoints whenever possible. Plain HTTP should be
reserved for explicit local development endpoints such as `localhost` or
`127.0.0.1`.

## Known Hardening Items

Done:

- The `SecretBox` root key lives in the macOS Keychain; legacy `.master.key`
  files are migrated and deleted automatically.
- OAuth authorization requests carry a random `state` that is validated on the
  callback before any code is used.
- The OAuth callback listener binds to `127.0.0.1` only, drops non-loopback
  connections, and rejects requests whose path or `state` does not match the
  pending flow.
- Global App Transport Security arbitrary loads are removed; custom provider
  endpoints must be `https://` (or loopback `http://`) and must not embed
  credentials.
- The proxy admin key is stored in the Keychain instead of plaintext SQLite.

Still open:

- Rotate/remove the committed Google OAuth client secret if it is a real
  confidential-client value (see the security audit's H-4 finding).
- Decide whether the app should be sandboxed for public distribution, and
  document any intentional exceptions.
- Consider rotating the SecretBox root key (and stored credentials) if any
  real credentials were stored before the Keychain migration landed, since
  older app-support directories may already have been copied or backed up.

## Dependency and Release Checks

Before publishing a release:

- Run `xcodebuild -scheme CoderSwitch -configuration Debug test`.
- Run `git diff --check`.
- Scan the working tree and Git history for secret-like values.
- Rotate any credential that was ever committed to Git history before pushing
  the repository publicly.
