# OAuth Implementation Findings

This document details how the codebase uses OpenAI's OAuth to authenticate accounts.

## Overview

The implementation supports **two OAuth flows**:
1. **Browser-based OAuth** (primary) - Uses PKCE + local callback server
2. **Device Code Flow** (fallback) - For environments where browser redirect isn't available

The OAuth authenticates against `auth.openai.com` and creates/updates accounts in the local database.

---

## OAuth Configuration

**File:** `app/core/config/settings.py`

Key settings (with defaults):
```python
auth_base_url: str = "https://auth.openai.com"
oauth_client_id: str = "app_EMoamEEZ73f0CkXaXp7hrann"
oauth_originator: str = "codex_chatgpt_desktop"
oauth_scope: str = "openid profile email"
oauth_timeout_seconds: float = 30.0
oauth_redirect_uri: str = "http://localhost:1455/auth/callback"
oauth_callback_host: str = "127.0.0.1"  # or "0.0.0.0" in Docker
oauth_callback_port: int = 1455
```

The client ID `app_EMoamEEZ73f0CkXaXp7hrann` and originator `codex_chatgpt_desktop` are OpenAI's desktop client identifiers.

---

## Backend OAuth Flow

### 1. Service Layer (`app/modules/oauth/service.py`)

The `OauthService` class orchestrates the entire OAuth flow:

**State Management:**
- Uses `OAuthStateStore` (singleton) to track in-progress OAuth attempts
- State includes: status, method (browser/device), code_verifier, device_auth_id, user_code, poll_task, callback_server

**Two Authentication Methods:**

#### Browser Flow (PKCE)
1. Generate PKCE pair (`code_verifier`, `code_challenge`)
2. Generate random `state_token`
3. Build authorization URL via `build_authorization_url()`
4. Start local callback server on `127.0.0.1:1455`
5. Return authorization URL for user to visit in browser

#### Device Code Flow
1. Call `request_device_code()` → returns verification_url + user_code
2. Start polling task via `exchange_device_token()` at intervals
3. User visits verification_url and enters user_code
4. Tokens retrieved when user completes verification

**Callback Handling (`_handle_callback`):**
- Validates state parameter matches expected
- Exchanges authorization code for tokens using `exchange_authorization_code()`
- Persists tokens via `_persist_tokens()`

**Token Persistence (`_persist_tokens`):**
```python
# Extract claims from ID token
claims = extract_id_token_claims(tokens.id_token)
auth_claims = claims.auth or OpenAIAuthClaims()

# Generate unique account ID from chatgpt_account_id + email
account_id = generate_unique_account_id(raw_account_id, email)

# Create Account with encrypted tokens
account = Account(
    id=account_id,
    chatgpt_account_id=raw_account_id,
    email=email,
    plan_type=coerce_account_plan_type(...),
    access_token_encrypted=self._encryptor.encrypt(tokens.access_token),
    refresh_token_encrypted=self._encryptor.encrypt(tokens.refresh_token),
    id_token_encrypted=self._encryptor.encrypt(tokens.id_token),
    last_refresh=utcnow(),
    status=AccountStatus.ACTIVE,
)
```

### 2. OAuth Client (`app/core/clients/oauth.py`)

Low-level HTTP functions for OAuth protocol:

**PKCE Helpers:**
```python
def pkce_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("utf-8")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")

def generate_pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(32)
    return verifier, pkce_challenge(verifier)
```

**Authorization URL Builder:**
```python
def build_authorization_url(*, state, code_challenge, ...) -> str:
    # Builds URL: https://auth.openai.com/oauth/authorize?...
    # With params: response_type, client_id, redirect_uri, scope, code_challenge, code_challenge_method=S256, state, id_token_add_organizations, codex_cli_simplified_flow, originator
```

**Token Exchange:**
```python
async def exchange_authorization_code(*, code, code_verifier, ...):
    # POST to https://auth.openai.com/oauth/token
    # grant_type=authorization_code, code, code_verifier

async def exchange_device_token(*, device_auth_id, user_code, ...):
    # POST to https://auth.openai.com/api/accounts/deviceauth/token
    # Returns tokens or None if pending
```

**Device Code Request:**
```python
async def request_device_code(...):
    # POST to https://auth.openai.com/api/accounts/deviceauth/usercode
    # Returns DeviceCode with verification_url, user_code, device_auth_id, interval, expires_in
```

### 3. API Endpoints (`app/modules/oauth/api.py`)

```
POST /api/oauth/start         → OauthStartResponse (starts OAuth)
GET  /api/oauth/status        → OauthStatusResponse (poll status)
POST /api/oauth/complete      → OauthCompleteResponse (complete device flow)
POST /api/oauth/manual-callback → ManualCallbackResponse (for remote access)
```

All routes require dashboard session authentication.

---

## Frontend OAuth Integration

### Hook: `use-oauth.ts` (`frontend/src/features/accounts/hooks/use-oauth.ts`)

React hook managing OAuth state and polling:

**State:**
```typescript
interface OAuthState {
  status: "idle" | "starting" | "pending" | "success" | "error";
  method: "browser" | "device" | null;
  authorizationUrl: string | null;
  callbackUrl: string | null;
  verificationUrl: string | null;
  userCode: string | null;
  deviceAuthId: string | null;
  intervalSeconds: number | null;
  expiresInSeconds: number | null;
  errorMessage: string | null;
}
```

**Methods:**
- `start(forceMethod?)` - Initiates OAuth, auto-starts device poll if needed
- `poll()` - Checks `/api/oauth/status` for current state
- `complete()` - Completes device flow polling
- `manualCallback(callbackUrl)` - For pasting callback URL when running remotely
- `reset()` - Clears state

**Auto-polling:**
- Polls status every `intervalSeconds` when in "pending" state
- Countdown timer for `expiresInSeconds`
- Clears timers on success/error

### API Client (`frontend/src/features/accounts/api.ts`)

```typescript
startOauth({ forceMethod })    // POST /api/oauth/start
getOauthStatus()               // GET  /api/oauth/status
completeOauth({ deviceAuthId, userCode })  // POST /api/oauth/complete
submitManualOauthCallback({ callbackUrl })  // POST /api/oauth/manual-callback
```

### Schemas (`frontend/src/features/accounts/schemas.ts`)

TypeScript schemas for request/response validation using Zod.

---

## Token Storage & Security

**Encryption:**
- Uses `TokenEncryptor` from `app.core.crypto`
- Access, refresh, and ID tokens are encrypted at rest
- Encryption key stored in `~/.codex-lb/encryption.key`

**Account Model (`app/db/models.py`):**
```python
class Account:
    id: str                          # Unique account ID
    chatgpt_account_id: str | None   # OpenAI account identifier
    email: str                       # User email
    plan_type: str                   # Account plan (e.g., "free", "plus")
    access_token_encrypted: str      # Encrypted access token
    refresh_token_encrypted: str     # Encrypted refresh token
    id_token_encrypted: str          # Encrypted ID token
    last_refresh: datetime           # Last token refresh timestamp
    status: AccountStatus            # ACTIVE, PAUSED, etc.
```

---

## Token Refresh (`app/core/auth/refresh.py`)

- Background service refreshes tokens before they expire
- Default refresh interval: 8 days (`token_refresh_interval_days`)
- Refresh timeout: 8 seconds (`token_refresh_timeout_seconds`)
- Uses encrypted refresh token from database

---

## Key Differences from CoderSwitch's Approach

Based on `FROM_CODERSWITCH/PROGRESS.md`, CoderSwitch has **deferred** OAuth implementation:
> "OAuth: Defer to after v1. Each provider has its own flow, some require PKCE, and ChatGPT doesn't have a documented public OAuth endpoint."

This codebase implements OAuth for OpenAI/ChatGPT specifically, using their documented desktop client OAuth flow with:
- Well-known client ID (`app_EMoamEEZ73f0CkXaXp7hrann`)
- Well-known originator (`codex_chatgpt_desktop`)
- PKCE for security
- Localhost callback on port 1455

---

## Summary of Key Files

| File | Purpose |
|------|---------|
| `app/core/config/settings.py` | OAuth configuration constants |
| `app/modules/oauth/service.py` | Main OAuth orchestration |
| `app/modules/oauth/api.py` | FastAPI routes |
| `app/core/clients/oauth.py` | Low-level OAuth HTTP functions |
| `app/core/auth/refresh.py` | Token refresh background service |
| `app/db/models.py` | Account model with encrypted tokens |
| `frontend/src/features/accounts/hooks/use-oauth.ts` | React OAuth state management |
| `frontend/src/features/accounts/api.ts` | Frontend API client |

---

## Implementation Notes

1. **No manual OAuth endpoint exists for CoderSwitch** - This codebase specifically uses OpenAI's desktop client OAuth which requires a registered client ID. CoderSwitch would need to either:
   - Implement OAuth for different providers (ChatGPT, Google AI, Claude) each with their own flow
   - Use API keys as the primary authentication method (which they already do)

2. **PKCE is required** - The browser flow uses S256 code challenge method

3. **Device flow as fallback** - If browser flow fails (OSError), automatically falls back to device code flow

4. **Manual callback for remote servers** - Allows pasting callback URL when localhost isn't reachable from browser

5. **Encrypted token storage** - All tokens encrypted at rest using AES or similar

6. **Account ID generation** - Uses `generate_unique_account_id(raw_account_id, email)` to create deterministic IDs from OpenAI's account data