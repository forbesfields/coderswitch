# Key Takeaways for CoderSwitch

This document captures everything in the codebase that would be useful for implementing CoderSwitch's feature set.

---

## 1. Architecture Overview

### This codebase is a **local proxy** for ChatGPT/OpenAI API access with multi-account load balancing.

**Key files:**
- `app/main.py` - FastAPI application entry point
- `app/modules/proxy/service.py` - Main proxy logic (641KB, massive)
- `app/modules/proxy/load_balancer.py` - Account selection and routing
- `app/core/clients/http.py` - HTTP client for upstream calls

### CoderSwitch parallels:
- Your `ProxyServer.swift` with Hummingbird handles similar routing
- Your `ModelRouter.swift` is analogous to their load balancer
- Both act as middleware between client requests and upstream providers

---

## 2. Account Model & Token Storage

### Encrypted Token Storage (`app/core/crypto.py`)
```python
from cryptography.fernet import Fernet

class TokenEncryptor:
    def __init__(self, key: bytes | None = None, key_file: Path | None = None) -> None:
        resolved_key = key or _get_or_create_key(resolved_file)
        self._fernet = Fernet(resolved_key)

    def encrypt(self, token: str) -> bytes:
        return self._fernet.encrypt(token.encode())

    def decrypt(self, encrypted: bytes) -> str:
        return self._fernet.decrypt(encrypted).decode()

def _get_or_create_key(key_file: Path) -> bytes:
    key_file.parent.mkdir(parents=True, exist_ok=True)
    if key_file.exists():
        return key_file.read_bytes()
    key = Fernet.generate_key()
    key_file.write_bytes(key)
    key_file.chmod(0o600)  # Secure permissions
    return key
```

**Key takeaway:** Uses Fernet (AES-128-CBC with HMAC) for symmetric encryption. Key file stored at `~/.codex-lb/encryption.key` with mode 600.

### Account Model (`app/db/models.py`)
```python
class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    chatgpt_account_id: Mapped[str | None] = mapped_column(String, nullable=True)
    email: Mapped[str] = mapped_column(String, nullable=False)
    plan_type: Mapped[str] = mapped_column(String, nullable=False)

    access_token_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    refresh_token_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    id_token_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    last_refresh: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    status: Mapped[AccountStatus] = mapped_column(...)
    deactivation_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    reset_at: Mapped[int | None] = mapped_column(Integer, nullable=True)
    blocked_at: Mapped[int | None] = mapped_column(Integer, nullable=True)
```

**Account Status Enum:**
```python
class AccountStatus(str, Enum):
    ACTIVE = "active"
    RATE_LIMITED = "rate_limited"
    QUOTA_EXCEEDED = "quota_exceeded"
    PAUSED = "paused"
    DEACTIVATED = "deactivated"
```

**CoderSwitch should:** Implement similar encryption for stored tokens. Keychain is good, but you could also use encrypted JSON storage with a generated key.

---

## 3. OAuth Implementation (Already documented in FINDINGS.md)

The OAuth flow is documented in `FINDINGS.md`. Key point: **This codebase uses OpenAI's desktop client OAuth specifically**, which requires their registered client ID. CoderSwitch would need to implement OAuth differently for each provider.

---

## 4. Token Refresh System

### Background Refresh (`app/core/auth/refresh.py`)
```python
TOKEN_REFRESH_INTERVAL_DAYS = 8

class RefreshError(Exception):
    def __init__(self, code: str, message: str, is_permanent: bool, *, transport_error: bool = False) -> None:
        self.code = code
        self.message = message
        self.is_permanent = is_permanent
        self.transport_error = transport_error

async def refresh_access_token(
    refresh_token: str,
    *,
    session: aiohttp.ClientSession | None = None,
) -> TokenRefreshResult:
    settings = get_settings()
    url = f"{settings.auth_base_url.rstrip('/')}/oauth/token"
    payload = {
        "grant_type": "refresh_token",
        "client_id": settings.oauth_client_id,
        "refresh_token": refresh_token,
        "scope": settings.oauth_scope,
    }
    # ... POST request handling ...
```

**CoderSwitch needs:** Implement token refresh with:
- Interval-based refresh (e.g., every 8 days)
- Handle 401 responses and trigger re-auth
- Exponential backoff for transient failures

---

## 5. Usage Tracking & Quota Polling

### Usage Updater (`app/modules/usage/updater.py`)

This is a sophisticated system with:
- **Singleflight pattern** - Prevents concurrent refreshes for same account
- **Freshness tracking** - Avoids redundant API calls
- **Auth cooldown** - After 401/403, cooldown before retry
- **Additional quotas** - Tracks feature-specific limits

```python
class _UsageRefreshSingleflight:
    """Module-level singleton to coalesce concurrent refresh requests for the same account."""

    async def run(
        self,
        account_id: str,
        factory: Callable[[], Awaitable[AccountRefreshResult]],
    ) -> AccountRefreshResult:
        # Coalesce concurrent requests
```

**Key pattern - freshness checking:**
```python
def _latest_usage_is_fresh(
    latest: UsageHistory | None,
    *,
    now: datetime,
    interval_seconds: int,
) -> bool:
    return latest is not None and (now - latest.recorded_at).total_seconds() < interval_seconds
```

**CoderSwitch needs:**
- Per-account polling with configurable interval (they use 60s)
- Coalesce concurrent requests to same account
- Handle quota recovery (QUOTA_EXCEEDED → ACTIVE when quota frees up)

### Usage Repository (`app/modules/usage/repository.py`)

Stores `UsageHistory` with window types (primary/secondary), used_percent, reset_at, window_minutes.

**CoderSwitch:** Your `TokenUsage.swift` model is similar - per-account daily buckets with rollups.

---

## 6. API Keys System

### ApiKeysService (`app/modules/api_keys/service.py`)

A complete API key management system:

```python
class ApiKeysService:
    async def create_key(self, payload: ApiKeyCreateData) -> ApiKeyCreatedData:
        plain_key = _generate_plain_key()
        # Format: sk-clb-{base64url random}
        return ApiKeyCreatedData(...)

    async def validate_key(self, plain_key: str) -> ApiKeyData:
        key_hash = _hash_key(plain_key)
        # Lookup by hash, not the actual key

    async def enforce_limits_for_request(...):
        # Reservation-based rate limiting
```

**API Key with Limits:**
```python
@dataclass(frozen=True, slots=True)
class LimitRuleInput:
    limit_type: str           # "total_tokens", "input_tokens", "output_tokens", "cost_usd", "credits"
    limit_window: str         # "daily", "weekly", "monthly", "5h", "7d"
    max_value: int
    model_filter: str | None = None
```

**Usage Reservation Pattern:**
```python
# Before request: reserve usage
reservation = await self.enforce_limits_for_request(key_id, model=request_model, ...)

# After request: finalize or release
await self.finalize_usage_reservation(reservation_id, ...)
# OR
await self.fail_usage_reservation(reservation_id, ...)
```

**CoderSwitch should:**
- Add API key support for proxy authentication (they use `Authorization: Bearer <admin_key>`)
- Consider rate limiting per key (daily/weekly limits)
- Track usage per key

---

## 7. Load Balancing

### Load Balancer (`app/modules/proxy/load_balancer.py`)

Sophisticated multi-account routing with health tiers:

```python
class AccountState(Enum):
    HEALTHY = auto()      # Can accept requests
    DEGRADED = auto()     # Partial failures, reduced priority
    DRAINING = auto()      # No new requests, completing existing
    EXCLUDED = auto()      # Temporarily excluded

def select_account(
    accounts: list[Account],
    strategy: RoutingStrategy,
    latest_primary: dict[str, UsageHistory],
    latest_secondary: dict[str, UsageHistory],
    runtime_states: dict[str, RuntimeState],
    model: str | None,
    sticky_session: StickySession | None,
) -> SelectionResult:
```

**Routing Strategies:**
- `capacity_weighted` - Default, weights by remaining quota
- `least_used` - Fewest used percent first
- `sticky` - Maintain session affinity

**Key features:**
- Circuit breaker per account (see `app/core/resilience/`)
- Quota recovery automation
- Sticky sessions for conversation continuity

**CoderSwitch needs:**
- Implement round-robin or capacity-weighted selection across accounts
- Handle "all accounts exhausted" scenario
- Add sticky session support to route same conversation to same account

---

## 8. Request/Response Handling

### Proxy Service (`app/modules/proxy/service.py`)

The main proxy handles:
- `/v1/chat/completions` - OpenAI compatible
- `/v1/messages` - Anthropic compatible
- `/v1/models` - Model listing
- Streaming with SSE pass-through

**Hop-by-hop header stripping:**
```python
hop_by_hop_headers = {
    "transfer-encoding",
    "content-encoding",
    "connection",
    "keep-alive",
    "upgrade",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "proxy-connection",
}
```

**CoderSwitch's `UpstreamForwarder.swift` does similar work.**

---

## 9. Database Schema

Using **SQLAlchemy async** with **SQLite** (can switch to PostgreSQL):

```python
from sqlalchemy.ext.asyncio import AsyncSession

# Async session usage
async with self._session.begin():
    result = await self._session.execute(select(Account).where(...))
```

**CoderSwitch:** Using JSON file storage + Keychain is simpler but lacks:
- Atomic transactions
- Complex queries (usage trends, filtering)
- Concurrent access safety

Consider: SQLite.swift for local storage if you need more robustness.

---

## 10. Frontend Architecture

### React + TypeScript with Zod validation

**Frontend structure:**
```
frontend/src/
  features/
    accounts/       # Account management UI
    api-keys/      # API key management
    settings/      # Settings pages
    dashboard/     # Main dashboard
  components/      # Shared UI components
  hooks/           # Custom React hooks
  lib/             # API client, utilities
  schemas/         # Zod schemas for validation
```

**API Client (`frontend/src/lib/api-client.ts`):**
```typescript
export async function get<T>(path: string, schema: z.ZodSchema<T>) {
  const response = await fetch(path, { credentials: "include" });
  return schema.parse(await response.json());
}

export async function post<T>(path: string, schema: z.ZodSchema<T>, options?: RequestInit) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(options?.body),
    credentials: "include",
    cache: options?.cache,
  });
  return schema.parse(await response.json());
}
```

**CoderSwitch:** Using SwiftUI + Hummingbird is a different stack, but the patterns translate.

---

## 11. Key Swift Implementation Equivalents

| Python (codex-lb) | Swift (CoderSwitch) | Purpose |
|-------------------|---------------------|---------|
| `TokenEncryptor` | `KeychainStore` | Secure token storage |
| `OAuthService` | TBD - OAuth flows | Authentication |
| `AccountsRepository` | `AccountStore` | Account persistence |
| `UsageUpdater` | `QuotaPoller` | Usage tracking |
| `LoadBalancer` | `ModelRouter` | Request routing |
| `ApiKeysService` | (none yet) | API key management |
| `ProxyService` | `ProxyServer` | HTTP proxy |

---

## 12. Patterns to Adopt

### 1. Token Encryption at Rest
Don't just rely on Keychain - encrypt the token blobs with a locally-generated key. This allows you to back up accounts as JSON files.

### 2. QuotaCheck Protocol Pattern
```python
# Each provider declares its own path + JSON parser
@dataclass
class QuotaCheck:
    path: str          # API path for quota
    parser: callable   # Parse response to UsageLimit

class OpenRouterQuotaCheck:
    path = "/api/v1/credits"
    def parse(self, response): ...
```

**CoderSwitch already does this** with `QuotaCheck.swift` - good!

### 3. Singleflight for Concurrent Operations
Prevents thundering herd when multiple requests hit the same account during refresh.

### 4. Reservation Pattern for Rate Limits
1. Reserve usage before request
2. Finalize after success
3. Release on failure
This prevents over-consumption during concurrent requests.

### 5. Health Tier System
```python
HEALTH_TIER_HEALTHY = 0    # Full capacity
HEALTH_TIER_DEGRADED = 1   # Reduced priority
HEALTH_TIER_PROBING = 2    # Testing recovery
HEALTH_TIER_DRAINING = 3  # No new requests
```

### 6. Conversation Archive
`app/core/conversation_archive.py` - Logs all requests for debugging/audit. Useful for CoderSwitch debugging.

---

## 13. Configuration

**Settings (`app/core/config/settings.py`):**
```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="CODEX_LB_",
        env_file=(BASE_DIR / ".env", BASE_DIR / ".env.local"),
    )

    # Database
    database_url: str = f"sqlite+aiosqlite:///{DEFAULT_DB_PATH}"

    # OAuth
    auth_base_url: str = "https://auth.openai.com"
    oauth_client_id: str = "app_EMoamEEZ73f0CkXaXp7hrann"
    oauth_originator: str = "codex_chatgpt_desktop"
    oauth_scope: str = "openid profile email"

    # Token refresh
    token_refresh_interval_days: int = 8
    token_refresh_timeout_seconds: float = 8.0

    # Usage polling
    usage_refresh_interval_seconds: int = 60

    # Encryption
    encryption_key_file: Path = DEFAULT_HOME_DIR / "encryption.key"
```

**CoderSwitch:** Use a similar settings pattern - environment variables with `.env` file support.

---

## 14. Testing Patterns

```python
# tests/unit/test_auth_refresh.py
async def test_should_refresh_returns_true_when_old():
    last = utcnow() - timedelta(days=9)
    assert should_refresh(last) is True

async def test_refresh_updates_tokens():
    result = await refresh_access_token("test_refresh_token")
    assert result.access_token
    assert result.refresh_token
```

**CoderSwitch should:** Add tests for:
- Token refresh flow
- Quota parsing for different providers
- Account selection/routing logic

---

## 15. Missing Features in CoderSwitch (based on this codebase)

1. **API Keys** - Not implemented yet. Add `ApiKey` model with hash-based lookup and rate limits.

2. **OAuth** - Deferred. Need to research each provider's OAuth flow:
   - OpenAI/ChatGPT: Has documented OAuth (using their client ID)
   - Google AI: Has OAuth endpoints
   - Claude: `claude.ai/oauth/authorize`

3. **Usage History Database** - Currently in-memory. Consider SQLite for persistence.

4. **Request Logging** - Track all requests for debugging and audit.

5. **Circuit Breaker** - Per-account failure tracking to avoid hammering failing accounts.

6. **Sticky Sessions** - Route same conversation to same account for continuity.

7. **Multi-replica Support** - Leader election, instance ring for horizontal scaling (overkill for CoderSwitch).

---

## 16. Quick Wins for CoderSwitch

1. **Add token encryption** - Encrypt tokens before storing in Keychain for defense-in-depth
2. **Persist quota data** - SQLite instead of in-memory for usage history
3. **Add refresh scheduling** - Background task to refresh tokens before expiry
4. **Implement health tiers** - Track per-account health and route accordingly
5. **Add conversation archiving** - Debug log all requests

---

## 17. File Reference

### Most Important Files for CoderSwitch Implementation:

| File | Lines | Purpose |
|------|-------|---------|
| `app/core/crypto.py` | 38 | Token encryption |
| `app/modules/oauth/service.py` | 432 | OAuth flow |
| `app/core/clients/oauth.py` | 342 | OAuth HTTP |
| `app/core/auth/refresh.py` | 178 | Token refresh |
| `app/modules/usage/updater.py` | 854 | Usage polling |
| `app/modules/accounts/repository.py` | 315 | Account CRUD |
| `app/db/models.py` | 741 | Database schema |
| `app/modules/proxy/load_balancer.py` | ~500 | Account selection |

### Frontend Reference:

| File | Purpose |
|------|---------|
| `frontend/src/features/accounts/hooks/use-oauth.ts` | OAuth state machine |
| `frontend/src/features/accounts/components/oauth-dialog.tsx` | OAuth UI |
| `frontend/src/features/accounts/api.ts` | API calls |
| `frontend/src/features/accounts/schemas.ts` | TypeScript types |