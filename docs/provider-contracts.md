# Provider contracts

This document records the narrow external contract used by AI Usage. It is
intentionally limited to quota windows that can be fetched from credentials
the supported tools already store locally.

The reference implementation was OpenUsage `v0.7.6`, plus provider updates
through commit `9d2bf09f10e21f769494a525a9d65c84d7aeb1df`. These are
undocumented provider endpoints and may change; fixture tests protect the
currently known behavior.

## Claude Code

Credential source order:

1. macOS Keychain current-user item
2. macOS Keychain legacy service-only item
3. `$CLAUDE_CONFIG_DIR/.credentials.json`, otherwise
   `~/.claude/.credentials.json`

The production Keychain service is `Claude Code-credentials`. With
`CLAUDE_CONFIG_DIR`, the app first tries the service suffixed with the first
eight lowercase SHA-256 characters of the normalized directory, then the
production service.

`CLAUDE_CODE_OAUTH_TOKEN` is not a live-usage credential and is never selected.
A stored non-empty `scopes` array must contain `user:profile`; absent or empty
scope metadata is treated as unknown and allowed.

Usage request:

- `GET https://api.anthropic.com/api/oauth/usage`
- `Authorization: Bearer <access token>`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: claude-code/2.1.69`

Mapped fields:

| JSON field | UI row |
| --- | --- |
| `five_hour.utilization` | Session |
| `seven_day.utilization` | Weekly |
| `seven_day_sonnet.utilization` | Sonnet |
| `limits[kind=weekly_scoped, scope.model.display_name=Fable].percent` | Fable |

Every row reads `resets_at`, accepting ISO-8601 with variable fractions and no
timezone (assumed UTC), epoch seconds, or epoch milliseconds.

Refresh request:

- `POST https://platform.claude.com/v1/oauth/token`
- JSON body with `grant_type`, `refresh_token`, `client_id`, and `scope`
- client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- scope string:
  `user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`

The access token is refreshed within five minutes of `expiresAt` (epoch
milliseconds). A usage `401` or `403` causes at most one refresh and one retry.
`invalid_grant` means the session expired. A `429` honors `Retry-After`
(seconds or HTTP date) and otherwise starts a five-minute cooldown, including
manual refreshes.

The display plan is title-cased `subscriptionType`, plus an `Nx` fragment
extracted from `rateLimitTier`.

## Codex

Credential source order:

1. `$CODEX_HOME/auth.json`, when `CODEX_HOME` is set
2. otherwise `~/.config/codex/auth.json`
3. then `~/.codex/auth.json`
4. macOS Keychain service `Codex Auth`

An auth document uses `tokens.access_token`, `refresh_token`, `id_token`, and
`account_id`, plus top-level `last_refresh`. A document containing only
`OPENAI_API_KEY` produces “Usage not available for API key.”

Usage request:

- `GET https://chatgpt.com/backend-api/wham/usage`
- `Authorization: Bearer <access token>`
- optional `ChatGPT-Account-Id`

The main `rate_limit.primary_window` and `secondary_window` objects use
`used_percent`. Response headers `x-codex-primary-used-percent` and
`x-codex-secondary-used-percent` are fallbacks.

Windows are classified by `limit_window_seconds`:

- `18000`: Session
- `604800`: Weekly
- unknown or missing duration: primary/secondary slot fallback

The first `additional_rate_limits` entry whose `limit_name` or
`metered_feature` contains `spark` case-insensitively is mapped through the
same classifier to Spark and Spark Weekly.

Reset time uses epoch-seconds `reset_at`, then relative
`reset_after_seconds`. The display plan maps `prolite` to `Pro 5x`, `pro` to
`Pro 20x`, and title-cases other underscore-separated values.

Refresh request:

- `POST https://auth.openai.com/oauth/token`
- `application/x-www-form-urlencoded`
- client ID `app_EMoamEEZ73f0CkXaXp7hrann`

JWT `exp` is the primary refresh clock with five minutes of slack. Only when
`exp` cannot be decoded does `last_refresh` older than eight days trigger a
refresh. With neither value, no proactive refresh occurs. Before proactive
refresh, the exact credential source is re-read so a token already rotated by
the Codex CLI is adopted.

The recognized refresh failures are `refresh_token_expired`,
`refresh_token_reused`, and `refresh_token_invalidated`. A usage `401` or `403`
causes at most one refresh and one retry.

## Additional providers

| Provider | Local credential source | First-party usage contract | Mapped metrics |
| --- | --- | --- | --- |
| Cursor | Cursor state SQLite database, then `cursor-access-token` and `cursor-refresh-token` Keychain items | `api2.cursor.sh` DashboardService Connect RPCs | Total, Auto, API |
| Antigravity | Keychain service `gemini`, account `antigravity` | Google Cloud Code quota-summary API, with model-quota fallback (`antigravity/cli/1.3.6` User-Agent) | Gemini session/weekly, Claude session/weekly, Argon weekly |
| GitHub Copilot | Copilot editor config, GitHub CLI config, then `gh:github.com` Keychain item | `api.github.com/copilot_internal/user` | Credits, Chat, Completions |
| Devin | `~/.local/share/devin/credentials.toml`, then Devin state SQLite database | Codeium SeatManagement Connect RPC | Daily, Weekly |
| Grok | `~/.grok/auth.json` | Grok CLI billing and settings APIs | Weekly |

Cursor, Antigravity, and Grok refresh expiring access tokens using the refresh
credential already stored by the corresponding tool. Refreshed tokens are
persisted only where necessary; Antigravity's derived access token is cached
privately by AI Usage and bound to a hash of the current refresh credential.

OpenCode is intentionally not included: its current limits require scanning
local usage databases and are machine-local estimates, which conflicts with
AI Usage's no-background-log-scanning design. OpenRouter and Z.ai are also
excluded because they require users to add API keys instead of reusing a local
agent login.

## DeepSeek (fork only)

DeepSeek has no CLI login to reuse, so the API key is pasted into Settings and
stored in a Keychain item owned by AI Usage (service
`AI Usage DeepSeek API Key`). The provider counts as installed only while that
key exists.

- `GET https://api.deepseek.com/user/balance`
- `Authorization: Bearer <api key>`

`balance_infos[].total_balance` (a decimal string) is shown as a remaining
balance, preferring the `USD` entry and otherwise the first currency. DeepSeek
exposes no token or usage-history endpoint, so consumption is not tracked.

## The X Subscription (fork only)

Since October 12, 2026, xAI sells Grok and Cursor together as The X
Subscription, with one weekly pool shared by Grok and Cursor's first-party
models.

- Cursor `GetPlanInfo` reports merged accounts with top-level
  `"isMerged": true`, the tier in `planInfo.planName` (for example `Plus`), and
  `planInfo.includedUsagePeriod: INCLUDED_USAGE_PERIOD_WEEKLY`. The card shows
  the plan as `X <tier>`.
- Grok `GET /v1/billing?format=credits` returns HTTP 500
  (`{"error":"Failed to serialize billing response"}`) for merged accounts,
  while `/v1/settings` may still report the old `subscription_tier_display`.
  When the Grok quota can't be read, the Grok card shows Cursor's
  `totalPercentUsed` and `billingCycleEnd` as its weekly window instead.

## Warp (fork only)

Prefers the stable Warp Agent CLI session from Keychain service
`dev.warp.Warp-Stable.tui`, then the desktop app's `dev.warp.Warp-Stable`,
always account `User`. These can contain different accounts or an expired
desktop session alongside a valid CLI login. The JSON field `id_token` contains
`id_token` and `refresh_token`. Only that account is read; model-provider keys
stored under the same service are never selected.

- `POST https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo`
- Bearer Firebase ID token, `GetRequestLimitInfo` GraphQL query with a
  `RequestContext` containing client and macOS information.
- Maps `requestLimitInfo.requestsUsedSinceLastRefresh / requestLimit` to the
  percentage and `nextRefreshTime` to the reset date. The period is read from
  `requestLimitRefreshDuration`: monthly, weekly, or every two weeks. When both
  `usageCentsUsedSinceLastRefresh` and `includedUsageCents` exist, uses that
  dollar allowance instead of legacy credit counts. Unlimited accounts show
  an explicit status without a fabricated percentage. Purchased usage is
  outside the included monthly quota.
- Expiring Firebase ID tokens are exchanged at
  `https://securetoken.googleapis.com/v1/token` with Warp's public Firebase
  application identifier. Derived tokens are cached only in memory and bound
  to the exact local login. The app does not overwrite Warp's Keychain item.
- After the request, the stored login is read again. Usage is published only
  if it still belongs to the same account (Firebase `user_id` or `sub` and the
  Keychain service), so Warp's routine ID-token rotation doesn't discard it,
  while a sign-out or account switch does.

Sources: Warp's first-party
[query](https://github.com/warpdotdev/warp/blob/master/crates/graphql/src/api/queries/get_request_limit_info.rs),
[quota fields](https://github.com/warpdotdev/warp/blob/master/crates/graphql/src/api/ai.rs),
[session storage](https://github.com/warpdotdev/warp/blob/master/crates/warp_server_auth/src/user/persistence.rs),
the [CLI's separate Keychain namespace](https://github.com/warpdotdev/warp/blob/master/app/src/lib.rs),
and [billing documentation](https://docs.warp.dev/support-and-community/plans-and-billing/credits).
Contract checked on October 20, 2026, including a successful live quota fetch
through the Swift provider using the CLI session. Endpoints are internal and may change.

## Droid / Factory (fork only)

Uses Droid's v2 encrypted credential storage under `~/.factory/`, in order:

1. `auth.v2.loginkeychain`, AES key from Keychain service `Factory CLI`,
   account `auth-encryption-key-security-cli`.
2. `auth.v2.keyring`, same service, account `auth-encryption-key`.
3. `auth.v2.file`, AES key from `auth.v2.key`.

The storage format is `base64(nonce):base64(tag):base64(ciphertext)` using
AES-256-GCM with a 16-byte nonce and authentication tag. Decrypted JSON contains
`access_token`, `refresh_token`, optional `active_organization_id`, and optional
`region`. Credentials and decrypted documents are never logged or cached on disk
by AI Usage Plus.

- `GET https://api.factory.ai/api/billing/limits` (or `api.eu.factory.ai` for
  `region: eu`), Bearer token, `X-Factory-Client: cli`, compatible
  `X-Client-Version`, and the active `X-Factory-Org-Id` when present.
- Maps `limits.standard` and `limits.core` independently. Each pool exposes
  `fiveHour`, `weekly`, and `monthly` with `usedPercent` and `windowEnd`.
  Resetless zero-use windows remain visible. Missing windows are omitted.
  Standard windows come first, then Core; the card shows each pool as its own
  row.
- WorkOS refresh uses
  `POST https://api.workos.com/user_management/authenticate`, form fields
  `grant_type=refresh_token`, `refresh_token`, and Factory's public OAuth
  `client_id`. Rotated tokens are re-encrypted into the original source with
  owner-only permissions. Unknown fields and the selected organization are
  preserved. A changed credential generation aborts persistence. Usage is
  published only if the credential source still belongs to the same account
  (WorkOS `sub`, organization, and file), so the CLI rotating its own tokens
  mid-request doesn't discard it.
- Both providers honor HTTP 429 `Retry-After`, including manual refreshes.

Sources: Factory's [individual plan limits](https://docs.factory.ai/pricing/individuals)
and first-party Droid CLI 0.218.1 installed on this Mac. The local CLI's
authentication, encrypted storage, and `/limits` request were inspected on
October 20, 2026. A live read returned HTTP 200 with both pools and all six
windows. No sessions or transcripts are scanned.

## Persistence and failure policy

Warp and Droid access their exact service/account items through native Security
APIs. Automatic reads suppress Keychain interaction; permission failures show
an **Allow Keychain Access…** action on the provider card. Only that explicit
action permits a system dialog. No timed `security` subprocess is used for these
items. The legacy login Keychain's process-wide interaction flag is serialized
and restored around native calls; no ACL, Keychain lock setting, or system-wide
security policy is changed.

Choosing **Always Allow** in that dialog adds AI Usage Plus to the item's
access list, so later silent reads succeed. Warp and Droid update their items in
place, which keeps that access list. The entry is tied to the app's code
signature: release builds share one certificate, while ad hoc local builds
need the permission granted again after each rebuild.

Secrets are cached only in memory against the item's persistent reference and
modification date. Refreshes and post-request account checks read unencrypted
metadata, rather than asking for the same secret again. A changed or removed
item invalidates the cached value, preserving account-change and sign-out checks.

References: Apple's [file-based Keychain model](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains),
[interaction policy](https://developer.apple.com/documentation/security/seckeychainsetuserinteractionallowed(_:)),
and [attribute-only reads](https://developer.apple.com/documentation/security/ksecreturnattributes).

Rotated credentials are persisted only to the source from which they were
loaded. Claude compares the complete ordered credential generation before
writing and again before publishing usage. Codex compares the exact source
before writing. This prevents an in-flight refresh from overwriting a new CLI
login.

Temporary network failures, `429`, server errors, and invalid response shapes
preserve the last-good in-memory snapshot and mark it stale. Authentication and
storage failures clear that provider's snapshot.
