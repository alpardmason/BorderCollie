# Codex Usage Query Implementation Report

This report describes how to implement the Codex usage quota query feature as a standalone capability. It covers the data model, frontend query flow, backend command boundary, credential discovery, HTTP request, response parsing, error handling, caching, and security considerations.

The feature answers one question: for a Codex user authenticated through ChatGPT OAuth, what percentage of each rate-limit window has been consumed, and when does each window reset?

## Scope

There are two Codex quota acquisition paths:

1. **Codex CLI OAuth quota**
   - Uses credentials already created by the Codex CLI.
   - Reads OAuth data from macOS Keychain first, then from `~/.codex/auth.json`.
   - Queries `https://chatgpt.com/backend-api/wham/usage`.

2. **Application-managed Codex OAuth quota**
   - Uses OAuth accounts stored by the app itself.
   - Fetches or refreshes the selected account token through the app's OAuth manager.
   - Queries the same `wham/usage` endpoint.

Both paths share the same response contract and rendering component. They differ only in where the access token and account ID come from.

This report does not cover third-party Coding Plan providers such as Kimi, Zhipu, MiniMax, ZenMux, or Volcengine. Those are separate provider usage paths, even though the UI may display them with the same quota widgets.

## Architecture Overview

The implementation has five layers:

1. **UI card**
   - Decides whether a provider should show official Codex quota, app-managed Codex OAuth quota, or ordinary usage script data.

2. **React query hook**
   - Starts a cached quota request.
   - Polls when the provider is active.
   - Retries once on request failure.

3. **Tauri API wrapper**
   - Calls backend commands:
     - `get_subscription_quota` for Codex CLI credentials.
     - `get_codex_oauth_quota` for app-managed Codex OAuth credentials.

4. **Backend credential resolver**
   - CLI path reads Keychain or `~/.codex/auth.json`.
   - Managed path asks the OAuth manager for a valid token for the selected account.

5. **Backend quota client**
   - Sends a GET request to `https://chatgpt.com/backend-api/wham/usage`.
   - Adds `Authorization: Bearer <access_token>`.
   - Adds `ChatGPT-Account-Id: <account_id>` when available.
   - Converts `primary_window` and `secondary_window` into display tiers.

## Implementation Dependencies

Recommended frontend dependencies:

- React.
- `@tanstack/react-query` for polling, retries, and caching.
- The host application's native bridge, such as Tauri `invoke`, Electron IPC, or a local HTTP API.

Recommended backend dependencies:

- `serde` and `serde_json` for data contracts and response parsing.
- `reqwest` or another mature HTTP client.
- `chrono` for RFC3339 timestamp conversion.
- A secure credential store integration. On macOS, the current implementation uses the `security` CLI to read Keychain generic passwords.

Do not hardcode credentials. The frontend should never receive an access token.

## Data Contract

Use a normalized response shape so the UI does not depend on provider-specific response bodies.

Frontend shape:

```ts
type CredentialStatus = "valid" | "expired" | "not_found" | "parse_error";

interface QuotaTier {
  name: string;
  utilization: number;
  resetsAt: string | null;
}

interface SubscriptionQuota {
  tool: string;
  credentialStatus: CredentialStatus;
  credentialMessage: string | null;
  success: boolean;
  tiers: QuotaTier[];
  extraUsage: null;
  error: string | null;
  queriedAt: number | null;
}
```

Backend shape:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CredentialStatus {
    Valid,
    Expired,
    NotFound,
    ParseError,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaTier {
    pub name: String,
    pub utilization: f64,
    pub resets_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionQuota {
    pub tool: String,
    pub credential_status: CredentialStatus,
    pub credential_message: Option<String>,
    pub success: bool,
    pub tiers: Vec<QuotaTier>,
    pub extra_usage: Option<serde_json::Value>,
    pub error: Option<String>,
    pub queried_at: Option<i64>,
}

impl SubscriptionQuota {
    pub fn not_found(tool: &str) -> Self {
        Self {
            tool: tool.to_string(),
            credential_status: CredentialStatus::NotFound,
            credential_message: None,
            success: false,
            tiers: vec![],
            extra_usage: None,
            error: None,
            queried_at: None,
        }
    }

    pub fn error(tool: &str, status: CredentialStatus, message: String) -> Self {
        Self {
            tool: tool.to_string(),
            credential_status: status,
            credential_message: Some(message.clone()),
            success: false,
            tiers: vec![],
            extra_usage: None,
            error: Some(message),
            queried_at: Some(now_millis()),
        }
    }
}
```

Field semantics:

- `tool`: `"codex"` for CLI-backed quota, `"codex_oauth"` for app-managed OAuth quota.
- `credentialStatus`: state of local credentials before or during the remote API call.
- `credentialMessage`: human-readable credential issue, if available.
- `success`: true only when the remote quota call succeeds and is parsed.
- `tiers`: normalized rate-limit windows.
- `extraUsage`: unused for Codex quota; keep the field for shared UI compatibility.
- `error`: remote request, auth, or parse error.
- `queriedAt`: Unix epoch milliseconds for successful or attempted remote calls; null when credentials are missing.

## Expected Remote API Shape

The Codex quota endpoint is expected to return a `rate_limit` object with up to two windows:

```json
{
  "rate_limit": {
    "primary_window": {
      "used_percent": 42.5,
      "limit_window_seconds": 18000,
      "reset_at": 1780000000
    },
    "secondary_window": {
      "used_percent": 12.0,
      "limit_window_seconds": 604800,
      "reset_at": 1780500000
    }
  }
}
```

Map remote fields as follows:

| Remote field | Normalized field | Notes |
| --- | --- | --- |
| `used_percent` | `QuotaTier.utilization` | Already a percentage. Do not divide by 100. |
| `limit_window_seconds` | `QuotaTier.name` | `18000` means `five_hour`; `604800` means `seven_day`. |
| `reset_at` | `QuotaTier.resetsAt` | Unix seconds converted to ISO 8601. |

Window name mapping:

```ts
function windowSecondsToTierName(seconds: number): string {
  if (seconds === 18_000) return "five_hour";
  if (seconds === 604_800) return "seven_day";

  const hours = Math.floor(seconds / 3600);
  if (hours >= 24) return `${Math.floor(hours / 24)}_day`;
  return `${hours}_hour`;
}
```

## Frontend API Layer

Expose two frontend API methods. The frontend must not know how tokens are stored.

```ts
import { invoke } from "@tauri-apps/api/core";

export const subscriptionApi = {
  getQuota: (tool: string): Promise<SubscriptionQuota> =>
    invoke("get_subscription_quota", { tool }),

  getCodexOauthQuota: (
    accountId: string | null,
  ): Promise<SubscriptionQuota> =>
    invoke("get_codex_oauth_quota", { accountId }),
};
```

Use separate query keys so CLI-backed Codex quota and managed Codex OAuth quota do not collide.

```ts
import { useQuery } from "@tanstack/react-query";

const REFETCH_INTERVAL_MS = 5 * 60 * 1000;

export function useSubscriptionQuota(
  appId: "claude" | "codex" | "gemini",
  enabled: boolean,
  autoQuery = false,
  autoQueryIntervalMinutes = 5,
) {
  const refetchInterval =
    autoQuery && autoQueryIntervalMinutes > 0
      ? Math.max(autoQueryIntervalMinutes, 1) * 60 * 1000
      : false;

  return useQuery({
    queryKey: ["subscription", "quota", appId],
    queryFn: () => subscriptionApi.getQuota(appId),
    enabled: enabled && appId === "codex",
    refetchInterval,
    refetchIntervalInBackground: Boolean(refetchInterval),
    refetchOnWindowFocus: Boolean(refetchInterval),
    staleTime:
      autoQueryIntervalMinutes > 0
        ? Math.max(autoQueryIntervalMinutes, 1) * 60 * 1000
        : REFETCH_INTERVAL_MS,
    retry: 1,
  });
}

export function useCodexOauthQuota(
  accountId: string | null,
  enabled = true,
  autoQuery = false,
) {
  return useQuery({
    queryKey: ["codex_oauth", "quota", accountId ?? "default"],
    queryFn: () => subscriptionApi.getCodexOauthQuota(accountId),
    enabled,
    refetchInterval: autoQuery ? REFETCH_INTERVAL_MS : false,
    refetchIntervalInBackground: autoQuery,
    refetchOnWindowFocus: autoQuery,
    staleTime: REFETCH_INTERVAL_MS,
    retry: 1,
  });
}
```

## Frontend Rendering Behavior

Render these states:

| State | UI behavior |
| --- | --- |
| no quota object | Render nothing. |
| `credentialStatus === "not_found"` | Render nothing. |
| `credentialStatus === "parse_error"` | Render nothing or a low-noise diagnostics affordance. |
| `credentialStatus === "expired" && !success` | Show an expired credential warning and a refresh button. |
| `!success` | Show query failed and a refresh button. |
| `success && tiers.length > 0` | Show each tier as percentage used plus reset countdown. |

Recommended tier labels:

```ts
const TIER_LABELS: Record<string, string> = {
  five_hour: "5h",
  seven_day: "7d",
};
```

Recommended countdown helper:

```ts
function countdownStr(resetsAt: string | null): string | null {
  if (!resetsAt) return null;
  const diffMs = new Date(resetsAt).getTime() - Date.now();
  if (diffMs <= 0) return null;

  const hours = Math.floor(diffMs / (1000 * 60 * 60));
  const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));

  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return `${days}d${hours % 24}h`;
  }
  if (hours > 0) return `${hours}h${minutes}m`;
  return `${minutes}m`;
}
```

## Backend Command Boundary

Implement two backend commands.

The generic subscription command reads CLI credentials:

```rust
#[tauri::command]
pub async fn get_subscription_quota(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    tool: String,
) -> Result<SubscriptionQuota, String> {
    let result = subscription_service::get_subscription_quota(&tool).await;

    let snapshot = match &result {
        Ok(quota) => quota.clone(),
        Err(error) => SubscriptionQuota::error(
            &tool,
            CredentialStatus::Valid,
            error.clone(),
        ),
    };

    if tool == "codex" {
        state.usage_cache.put_subscription(AppType::Codex, snapshot);
        let _ = app.emit("usage-cache-updated", serde_json::json!({
            "kind": "subscription",
            "appType": "codex",
            "data": snapshot,
        }));
    }

    result
}
```

The managed Codex OAuth command receives an optional account ID. If missing, use the OAuth manager default account.

```rust
#[tauri::command(rename_all = "camelCase")]
pub async fn get_codex_oauth_quota(
    account_id: Option<String>,
    state: State<'_, CodexOAuthState>,
) -> Result<SubscriptionQuota, String> {
    let manager = state.0.read().await;

    let resolved_account_id = match account_id {
        Some(id) => Some(id),
        None => manager.default_account_id().await,
    };

    let Some(account_id) = resolved_account_id else {
        return Ok(SubscriptionQuota::not_found("codex_oauth"));
    };

    let access_token = match manager.get_valid_token_for_account(&account_id).await {
        Ok(token) => token,
        Err(error) => {
            return Ok(SubscriptionQuota::error(
                "codex_oauth",
                CredentialStatus::Expired,
                format!("Codex OAuth token unavailable: {error}"),
            ));
        }
    };

    Ok(query_codex_quota(
        &access_token,
        Some(&account_id),
        "codex_oauth",
        "Codex OAuth access token expired or rejected. Please re-login via the app.",
    )
    .await)
}
```

## Codex CLI Credential Resolution

The CLI-backed path should read credentials in this priority order:

1. macOS Keychain generic password:
   - service: `Codex Auth`
   - read with `security find-generic-password -s "Codex Auth" -w`
2. File:
   - `~/.codex/auth.json`

The expected credential JSON shape:

```json
{
  "auth_mode": "chatgpt",
  "tokens": {
    "access_token": "opaque-token",
    "account_id": "optional-chatgpt-account-id"
  },
  "last_refresh": "2026-07-02T10:00:00Z"
}
```

Only `auth_mode === "chatgpt"` supports quota querying. API-key mode does not expose ChatGPT subscription rate-limit usage through this path.

Reference parser:

```rust
#[derive(Deserialize)]
struct CodexAuthJson {
    auth_mode: Option<String>,
    tokens: Option<CodexTokens>,
    last_refresh: Option<String>,
}

#[derive(Deserialize)]
struct CodexTokens {
    access_token: Option<String>,
    account_id: Option<String>,
}

type CodexCredentials = (
    Option<String>,
    Option<String>,
    CredentialStatus,
    Option<String>,
);

fn parse_codex_credentials_json(content: &str) -> CodexCredentials {
    let auth: CodexAuthJson = match serde_json::from_str(content) {
        Ok(value) => value,
        Err(error) => {
            return (
                None,
                None,
                CredentialStatus::ParseError,
                Some(format!("Failed to parse Codex auth JSON: {error}")),
            );
        }
    };

    if auth.auth_mode.as_deref() != Some("chatgpt") {
        return (
            None,
            None,
            CredentialStatus::NotFound,
            Some("Codex not using OAuth mode".to_string()),
        );
    }

    let Some(tokens) = auth.tokens else {
        return (
            None,
            None,
            CredentialStatus::ParseError,
            Some("No tokens in Codex auth".to_string()),
        );
    };

    let Some(access_token) = tokens.access_token.filter(|token| !token.is_empty()) else {
        return (
            None,
            None,
            CredentialStatus::ParseError,
            Some("access_token is empty or missing".to_string()),
        );
    };

    if let Some(last_refresh) = auth.last_refresh.as_deref() {
        if is_codex_token_stale(last_refresh) {
            return (
                Some(access_token),
                tokens.account_id,
                CredentialStatus::Expired,
                Some("Codex token may be stale (>8 days since last refresh)".to_string()),
            );
        }
    }

    (
        Some(access_token),
        tokens.account_id,
        CredentialStatus::Valid,
        None,
    )
}
```

Token staleness helper:

```rust
fn is_codex_token_stale(last_refresh: &str) -> bool {
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let Ok(datetime) = chrono::DateTime::parse_from_rfc3339(last_refresh) else {
        return false;
    };

    let age_secs = now_secs.saturating_sub(datetime.timestamp() as u64);
    age_secs > 8 * 24 * 3600
}
```

Read order:

```rust
fn read_codex_credentials() -> CodexCredentials {
    #[cfg(target_os = "macos")]
    {
        if let Some(credentials) = read_codex_credentials_from_keychain() {
            return credentials;
        }
    }

    read_codex_credentials_from_file()
}

#[cfg(target_os = "macos")]
fn read_codex_credentials_from_keychain() -> Option<CodexCredentials> {
    let output = std::process::Command::new("security")
        .args(["find-generic-password", "-s", "Codex Auth", "-w"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let json = String::from_utf8(output.stdout).ok()?;
    let json = json.trim();
    if json.is_empty() {
        return None;
    }

    Some(parse_codex_credentials_json(json))
}
```

## Shared Codex Quota HTTP Client

Both Codex credential paths should call the same quota function.

```rust
#[derive(Deserialize)]
struct CodexRateLimitWindow {
    used_percent: Option<f64>,
    limit_window_seconds: Option<i64>,
    reset_at: Option<i64>,
}

#[derive(Deserialize)]
struct CodexRateLimit {
    primary_window: Option<CodexRateLimitWindow>,
    secondary_window: Option<CodexRateLimitWindow>,
}

#[derive(Deserialize)]
struct CodexUsageResponse {
    rate_limit: Option<CodexRateLimit>,
}

async fn query_codex_quota(
    access_token: &str,
    account_id: Option<&str>,
    tool_label: &str,
    expired_message: &str,
) -> SubscriptionQuota {
    let client = reqwest::Client::new();

    let mut request = client
        .get("https://chatgpt.com/backend-api/wham/usage")
        .header("Authorization", format!("Bearer {access_token}"))
        .header("User-Agent", "codex-cli")
        .header("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(15));

    if let Some(account_id) = account_id {
        request = request.header("ChatGPT-Account-Id", account_id);
    }

    let response = match request.send().await {
        Ok(response) => response,
        Err(error) => {
            return SubscriptionQuota::error(
                tool_label,
                CredentialStatus::Valid,
                format!("Network error: {error}"),
            );
        }
    };

    let status = response.status();

    if status == reqwest::StatusCode::UNAUTHORIZED
        || status == reqwest::StatusCode::FORBIDDEN
    {
        return SubscriptionQuota::error(
            tool_label,
            CredentialStatus::Expired,
            format!("{expired_message} (HTTP {status})"),
        );
    }

    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        return SubscriptionQuota::error(
            tool_label,
            CredentialStatus::Valid,
            format!("API error (HTTP {status}): {body}"),
        );
    }

    let body: CodexUsageResponse = match response.json().await {
        Ok(body) => body,
        Err(error) => {
            return SubscriptionQuota::error(
                tool_label,
                CredentialStatus::Valid,
                format!("Failed to parse API response: {error}"),
            );
        }
    };

    let mut tiers = Vec::new();

    if let Some(rate_limit) = body.rate_limit {
        for window in [rate_limit.primary_window, rate_limit.secondary_window]
            .into_iter()
            .flatten()
        {
            let Some(used_percent) = window.used_percent else {
                continue;
            };

            tiers.push(QuotaTier {
                name: window
                    .limit_window_seconds
                    .map(window_seconds_to_tier_name)
                    .unwrap_or_else(|| "unknown".to_string()),
                utilization: used_percent,
                resets_at: window.reset_at.and_then(unix_ts_to_iso),
            });
        }
    }

    SubscriptionQuota {
        tool: tool_label.to_string(),
        credential_status: CredentialStatus::Valid,
        credential_message: None,
        success: true,
        tiers,
        extra_usage: None,
        error: None,
        queried_at: Some(now_millis()),
    }
}
```

Helpers:

```rust
fn window_seconds_to_tier_name(seconds: i64) -> String {
    match seconds {
        18_000 => "five_hour".to_string(),
        604_800 => "seven_day".to_string(),
        seconds => {
            let hours = seconds / 3600;
            if hours >= 24 {
                format!("{}_day", hours / 24)
            } else {
                format!("{}_hour", hours)
            }
        }
    }
}

fn unix_ts_to_iso(timestamp: i64) -> Option<String> {
    chrono::DateTime::from_timestamp(timestamp, 0).map(|datetime| datetime.to_rfc3339())
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
```

## CLI-Backed Entry Point

The CLI-backed service should treat stale tokens optimistically: if a token is marked stale, still try the remote API once. If the request succeeds, return success. If not, return `expired`.

```rust
pub async fn get_subscription_quota(tool: &str) -> Result<SubscriptionQuota, String> {
    match tool {
        "codex" => {
            let (token, account_id, status, message) = read_codex_credentials();

            match status {
                CredentialStatus::NotFound => Ok(SubscriptionQuota::not_found("codex")),
                CredentialStatus::ParseError => Ok(SubscriptionQuota::error(
                    "codex",
                    CredentialStatus::ParseError,
                    message.unwrap_or_else(|| "Failed to parse credentials".to_string()),
                )),
                CredentialStatus::Expired => {
                    if let Some(token) = token {
                        let result = query_codex_quota(
                            &token,
                            account_id.as_deref(),
                            "codex",
                            "Authentication failed. Please re-login with Codex CLI.",
                        )
                        .await;

                        if result.success {
                            return Ok(result);
                        }
                    }

                    Ok(SubscriptionQuota::error(
                        "codex",
                        CredentialStatus::Expired,
                        message.unwrap_or_else(|| {
                            "Codex OAuth token may be stale".to_string()
                        }),
                    ))
                }
                CredentialStatus::Valid => {
                    let token = token.expect("token must be present when status is valid");
                    Ok(query_codex_quota(
                        &token,
                        account_id.as_deref(),
                        "codex",
                        "Authentication failed. Please re-login with Codex CLI.",
                    )
                    .await)
                }
            }
        }
        _ => Ok(SubscriptionQuota::not_found(tool)),
    }
}
```

## Error Semantics

Use predictable status mapping:

| Condition | `credentialStatus` | `success` | `queriedAt` | Notes |
| --- | --- | --- | --- | --- |
| no Keychain item and no auth file | `not_found` | false | null | UI should hide. |
| auth file unreadable or invalid JSON | `parse_error` | false | now | UI can hide or show diagnostics. |
| `auth_mode !== "chatgpt"` | `not_found` | false | null | API-key mode cannot use this quota path. |
| token missing | `parse_error` | false | now | Local credential corruption. |
| token stale by timestamp | `expired` initially | maybe true | now on remote attempt | Try remote API once before failing. |
| HTTP 401 or 403 | `expired` | false | now | User must re-login. |
| HTTP non-2xx other than 401/403 | `valid` | false | now | Remote API failure, not necessarily credential failure. |
| network error | `valid` | false | now | Retry once on frontend. |
| JSON parse error | `valid` | false | now | Endpoint contract changed or unexpected response. |

## Security Requirements

Do not log or render tokens. Never include `Authorization` headers in error messages.

Token handling rules:

- Keep tokens server-side only.
- Frontend should request quota, not tokens.
- Use environment, Keychain, secure storage, or app credential manager for token storage.
- Do not persist remote response bodies if they may include account data.
- Truncate non-2xx body previews if displaying them to users.
- Use HTTPS only.

Managed-account rules:

- `accountId` is not a secret, but treat it as account metadata.
- Include `ChatGPT-Account-Id` only when present.
- If no managed account exists, return `not_found` instead of throwing.

## Testing Plan

Unit tests:

- `windowSecondsToTierName(18000) == "five_hour"`.
- `windowSecondsToTierName(604800) == "seven_day"`.
- unknown one-hour window maps to `"1_hour"`.
- unknown multi-day window maps to `"<n>_day"`.
- Unix timestamp conversion returns RFC3339/ISO string.
- credential parser rejects non-`chatgpt` auth mode as `not_found`.
- credential parser returns `parse_error` for missing token.
- stale `last_refresh` returns `expired` with token preserved.

Component tests:

- `not_found` renders nothing.
- `expired` renders expired warning.
- `success` with two tiers renders both tier badges.
- refresh button calls query refetch.

Integration tests:

- Mock `get_subscription_quota("codex")` and verify card shows official quota.
- Mock `get_codex_oauth_quota(accountId)` and verify managed OAuth card uses account-specific query key.
- Mock HTTP 401 and verify normalized expired response.
- Mock successful `wham/usage` response and verify normalized tiers.

## Reimplementation Checklist

1. Define `SubscriptionQuota`, `QuotaTier`, `CredentialStatus`, and `ExtraUsage` data structures.
2. Implement frontend API calls for `get_subscription_quota` and `get_codex_oauth_quota`.
3. Implement React query hooks with stable query keys and five-minute stale time.
4. Implement a shared quota view that renders missing, expired, failed, and successful states.
5. Implement CLI credential lookup:
   - macOS Keychain service `Codex Auth`.
   - fallback file `~/.codex/auth.json`.
6. Parse only `auth_mode: "chatgpt"` credentials.
7. Preserve `account_id` when present.
8. Mark tokens stale when `last_refresh` is older than eight days, but still attempt one remote quota call.
9. Implement managed OAuth account lookup and token refresh in the app credential manager.
10. Implement shared `query_codex_quota`.
11. Send `Authorization`, `User-Agent`, `Accept`, and optional `ChatGPT-Account-Id` headers.
12. Normalize `primary_window` and `secondary_window` to tiers.
13. Map 401/403 to expired credentials.
14. Emit a UI/cache update event after every query attempt if the host app has a shared cache or tray.
15. Add parser, HTTP mock, and component tests.

## Key Design Decisions

| Decision | Rationale | Alternative |
| --- | --- | --- |
| Normalize all quota results into `SubscriptionQuota` | Keeps UI independent from remote API shape. | Render remote API directly, but that couples UI to unstable fields. |
| Share `query_codex_quota` across CLI and managed OAuth paths | Only credential source differs; endpoint and response parsing are identical. | Duplicate the request logic, increasing drift risk. |
| Hide `not_found` and `parse_error` in compact UI | Missing credentials are common and should not create noisy cards. | Show diagnostic rows everywhere. Better for debugging, worse for normal use. |
| Try stale tokens once | Timestamp staleness is heuristic; remote API is authoritative. | Fail immediately after eight days. Simpler but causes false negatives. |
| Include `ChatGPT-Account-Id` only when available | Supports multi-account users without breaking single-account users. | Always require account ID. Stricter but less compatible. |
