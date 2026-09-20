# OpenAI (ChatGPT/Codex) Usage Provider — Design

_Date: 2026-09-19. Branch: `claude/openai-subscription-usage-ebfef2`._

## Goal

Show ChatGPT subscription (Codex) plan-quota usage next to Claude usage in the menu bar
item, the dropdown, the floating desktop panel, and the widget. Threshold notifications
cover both providers.

## Data source (verified 2026-09-19)

`GET https://chatgpt.com/backend-api/wham/usage`

Headers: `Authorization: Bearer <access_token>`, `ChatGPT-Account-Id: <account_id>`,
`Accept: application/json`.

Credentials come read-only from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`):

```json
{ "auth_mode": "chatgpt",
  "tokens": { "access_token": "<JWT>", "account_id": "<uuid>", "refresh_token": "…" } }
```

Token expiry is the JWT `exp` claim (epoch seconds). We never refresh or write the token.

Response fields used (everything else ignored):

```json
{ "plan_type": "plus",
  "rate_limit": {
    "primary_window":   { "used_percent": 32, "limit_window_seconds": 18000,
                          "reset_after_seconds": 12341, "reset_at": 1789726348 },
    "secondary_window": { "used_percent": 56, "limit_window_seconds": 604800,
                          "reset_after_seconds": 169749, "reset_at": 1789883756 } } }
```

`used_percent` arrives as an integer; decode as `Double`. `rate_limit` may be `null`.

## Architecture

### `UsageCore` (all new logic, TDD)

**`UsageBoard`** (`Models/UsageBoard.swift`) — `Codable, Sendable, Equatable`.
- `snapshots: [UsageSnapshot]` kept in `ProviderID.displayOrder` (Claude, OpenAI).
- `snapshot(for: ProviderID) -> UsageSnapshot?`
- `mutating func replace(_ snapshot: UsageSnapshot)` — replaces by provider, keeps order.
- `tightestLimits: [(provider: ProviderID, limit: UsageLimit)]` — one entry per provider
  that has limits, in display order.
- `latestFetchedAt: Date?` — newest `fetchedAt` across snapshots.

**`ProviderID`** — add `CaseIterable`, `static displayOrder: [ProviderID] = [.claude, .openai]`
(xAI stays in the enum, not in display order), and computed `displayName` ("Claude",
"OpenAI", "xAI"), `glyph` ("◐", "⬡", "✕"), `clientName` ("Claude Code", "Codex CLI",
"xAI").

**`SnapshotStore`** — `save(_ board: UsageBoard)` / `load() -> UsageBoard?` on
`usage_board.json`. The single-snapshot API is removed, but `load()` imports the legacy
`usage_snapshot.json` (previous app version's one `UsageSnapshot`, Claude) once per provider
missing from the board; if the board already has an entry for that provider, the entry is
replaced by `current.mergingLastGood(previous: legacy)` so an empty stale/rate-limited entry
gains the legacy limits and their timestamp; the legacy file is read-only and never deleted.

**`CodexAuthReader`** (`Keychain/CodexAuthReader.swift`, folder kept for cohesion with the
Claude reader):
```swift
public struct CodexAuth: Sendable { accessToken: String; accountID: String?; expiresAt: Date? }
public protocol CodexAuthReader: Sendable { func readCodexAuth() throws -> CodexAuth }
public struct FileCodexAuthReader: CodexAuthReader { init(fileURL: URL = <default>) }
```
- Default path: `$CODEX_HOME/auth.json` if set, else `~/.codex/auth.json`.
- Errors reuse `TokenReaderError`: file missing, `tokens` null, or empty `access_token` →
  `.notFound`; unreadable file → `.accessDenied`; bad JSON → `.malformed`.
- `CodexCredentials.parse(Data) -> CodexAuth` is a pure function; JWT `exp` decoding
  (base64url payload) is a pure helper. Unparseable JWT → `expiresAt = nil` (not an error).

**`OpenAIUsageProvider`** (`Providers/OpenAI/`) — mirrors `ClaudeUsageProvider`:
- `id = .openai`; deps: `CodexAuthReader`, `UsageHTTPClient`, `baseURL`
  (default `https://chatgpt.com`, app override via `CHATGPT_BASE_URL` env), thresholds.
- Status mapping: `.notFound` → `.needsSignIn`; `.accessDenied`/`.malformed`/other →
  `.error("Can't read Codex credentials")`; expired token → `.stale("Token expired — open
  Codex to refresh")`; 401 → `.stale("Unauthorized — open Codex to refresh")`; 429 →
  `.stale("Rate limited — retrying")`; other non-2xx → `.error("HTTP <code>")`; `URLError` →
  `.stale("Network unavailable — retrying")`; `DecodingError` → `.error("Couldn't read
  usage data")`.
- `ChatGPT-Account-Id` header is sent only when `accountID` is non-nil.

**DTO** `OpenAIUsageResponse` — `rateLimit: RateLimit?` with `primaryWindow`/
`secondaryWindow: Window?`; `Window { usedPercent: Double; limitWindowSeconds: Int?;
resetAt: Double? }`. Snake-case `CodingKeys`. `additional_rate_limits`, `credits`,
`model_usage`, `plan_type` are not decoded.

**Mapper** `OpenAIUsageMapper.map(_ rateLimit: RateLimit?, warning:, critical:) -> [UsageLimit]`:
- primary → `id: "session"`, secondary → `id: "weekly_all"` (same IDs as Claude, so the
  widget row lookup works for both).
- Label from `limitWindowSeconds`: `< 86400` → "Session (<N>h)" with N = seconds/3600
  rounded; `== 604800` → "Weekly"; otherwise "<N>-day" with N = seconds/86400 rounded;
  `nil` → "Session" / "Weekly" by position.
- `resetsAt = Date(timeIntervalSince1970: resetAt)` or `nil`.
- Severity via `Severity.from`. `nil` rate limit → `[]`.

**`ThresholdEvaluator`** — de-dupe key becomes `"<provider>#<limitID>#<threshold>"`.
`ThresholdCrossing` gains `provider: ProviderID`. Existing fired keys are orphaned once
(one possible re-notification after upgrade; accepted).

**Last-good merge** — `UsageSnapshot.mergingLastGood(previous: UsageSnapshot?) ->
UsageSnapshot`: for `.stale`/`.error` with empty limits and a previous non-empty snapshot of
the same provider, return previous limits + previous `fetchedAt` + the new status; otherwise
return `self`. Moved out of the view model.

**`ProviderRegistry.makeDefault(tokenReader:, codexAuthReader:, httpClient:,
claudeBaseURL:, openAIBaseURL:)`** → `[ClaudeUsageProvider, OpenAIUsageProvider]`.

**`UsageRefresher`** (`UsageRefresher.swift`) — the refresh pipeline, in core so it is
unit-testable without the app:
```swift
public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard,
                               providers: [any UsageProvider]) async -> UsageBoard
}
```
Runs every provider concurrently (`withTaskGroup`); a thrown `fetch()` becomes
`.error("Fetch failed")` for that provider; each result is passed through
`mergingLastGood(previous:)` against the board's current entry and then `replace`d. One
slow or failing provider never blocks or blanks another.

**`UsageFormatter.compactLabel(for board: UsageBoard) -> String`** (moved from the app):
Every provider in `displayOrder` is always shown; a provider with no data renders as `<glyph>—`, e.g. `◐—|⬡100%`; an empty board renders `◐—|⬡—`.

### App

- **`UsageViewModel`**: `@Published var board = UsageBoard()`; loads the stored board at
  init. `refresh()` is `board = await UsageRefresher.refresh(board, providers:
  registry.providers)`, then save, `notifications.process(board)`, reload widget timelines.
  Registry gets `FileCodexAuthReader()` and the `CHATGPT_BASE_URL` override. No fetch or
  merge logic lives in the app target.
- **`MenuContentView`**: `ForEach(board.snapshots)` renders a
  `ProviderSection` (shared view, `App/ProviderSection.swift`): header
  `Text(provider.displayName).font(.caption.bold())`, status row, then `LimitRow`s, or
  "No usage data." when `.ok` with no limits. Status text is provider-aware:
  `.needsSignIn` → "Sign in to \(clientName) first."; `.keychainDenied` text unchanged.
  Sections separated by a thin `Divider`. One "Updated …" line at the bottom from
  `board.latestFetchedAt`. Panel title "Tokens"; quit alert "Quit Tokens?".
  Loading state ("Loading…") when the board is empty. When a provider's status is not `.ok`
  and it still has limits, rows dimmed to 40 % with the status text centered on top, no background.
  The floating panel (`DesktopPanelView`) is a 72-pt-wide vertical strip, one thin bar per provider (tightest limit, tick for the other window), percent above, glyph and data age below, hover for the full breakdown; stale/rate-limited providers get a frosted glass with a status icon.
- **`MenuBarLabelView`**: AppKit `NSStatusItem` hosting the SwiftUI label (autosave name `Tokens`, default preferred position 120 pt from the right so a crowded bar does not hide it); click opens the menu as a popover.
- **`NotificationManager.process(_ board:)`**: for each snapshot with `.ok`, run the
  evaluator with the shared `NotificationState`; title
  `"\(provider.displayName) \(limit.label) at NN%"`. Team-signed gate unchanged.

### Widget

- `UsageEntry.board: UsageBoard?`; provider reads `store.load()`.
- `.systemMedium`: for each provider in the board, a header line and the `session` /
  `weekly_all` rows. `.systemSmall`: one row per provider showing the tightest limit.
- Display name and description: "Tokens" / "Plan-quota usage for Claude and OpenAI."
- Stale marker: `latestFetchedAt` older than 30 min.

## Rate-limit backoff

Anthropic's usage endpoint allows only a few calls per hour per token, and every rejected
call counts against that budget. `FetchStatus.rateLimited(until: Date, wait: TimeInterval)`
replaces the old `.stale` mapping for HTTP 429 on both providers: the provider parses
`Retry-After` (`Network/RetryAfter.swift`, integer-seconds form only; a missing header or an
HTTP-date form yields `0` and lets the policy decide).

`RateLimitBackoff.wait(retryAfter:previous:)` picks the wait: the server's `Retry-After`
wins when present (capped at 2 h); otherwise it starts at 15 min and doubles on each
consecutive rate limit for that provider, capped at 2 h.

`UsageRefresher.refresh` takes a `now: Date = Date()` parameter. For each provider, if the
board's current entry is `.rateLimited(until:, _)` and `until > now`, the provider is
**skipped** entirely (no `fetch()` call, entry untouched) — this is what keeps Claude backing
off while OpenAI keeps polling on its own schedule. A fresh `.rateLimited` result has its
`wait`/`until` normalized through `RateLimitBackoff` (using the board's previous status)
before the usual `mergingLastGood` merge, so limits and `fetchedAt` from the last good fetch
are preserved.

## Out of scope

Per-provider enable/disable in Settings (parked in the rich-settings spec), token refresh,
credits, `additional_rate_limits`, model availability, xAI.

## Testing

All automated tests live in `UsageCore` and run with `swift test` (no Xcode, no signing).
They are organized in three layers. TDD applies to every layer: the test is written and
fails before the code is written.

### Layer 1 — Abstraction: the `UsageProvider` contract

One shared contract, run against **every** provider. It states what the rest of the system
may assume about any provider, present or future (xAI later plugs in here).

`Tests/UsageCoreTests/Contract/UsageProviderContract.swift` — a test helper, not a test
class. It takes a `ProviderContractSubject`:

```swift
struct ProviderContractSubject {
    let expectedID: ProviderID
    let validFixture: String          // fixture that must map to ≥ 1 limit
    let expectedLimitCount: Int
    /// Builds the provider for one scenario. `credential` says how the credential read
    /// ends; `client` is the HTTP double to inject.
    let make: (_ credential: CredentialOutcome, _ client: UsageHTTPClient) -> any UsageProvider
}
enum CredentialOutcome { case valid, expired, notFound, accessDenied, malformed }
```

Contract assertions (each a `static func` on the helper, called from per-provider test
classes so failures name the provider):

| # | Assertion | Why it matters |
|---|---|---|
| C1 | `fetch()` never throws; every failure is a `FetchStatus` | the refresher can treat providers uniformly |
| C2 | `snapshot.provider == provider.id` | board placement |
| C3 | any non-`.ok` status ⇒ `limits.isEmpty` | UI/notification code may trust this |
| C4 | `.ok` with `validFixture` ⇒ `limits.count == expectedLimitCount`, every `severity` matches `Severity.from` for the configured thresholds | mapper wired with thresholds |
| C5 | `.notFound` ⇒ `.needsSignIn` | "sign in to <client>" UX |
| C6 | `.expired` ⇒ `.stale`, and **zero** HTTP calls (spy) | no wasted/unauthorized calls |
| C7 | HTTP 401 ⇒ `.stale`; 429 ⇒ `.rateLimited`; 500 ⇒ `.error`; `URLError` ⇒ `.stale`; bad JSON body ⇒ `.error` | last-good merge relies on the `.stale`/`.error`/`.rateLimited` split |
| C8 | request carries `Authorization: Bearer <token>` and exactly one GET | auth plumbing |
| C9 | `fetchedAt` is within the test's time window | "Updated …" line |

`ClaudeUsageProviderContractTests` and `OpenAIUsageProviderContractTests` each build a
subject and call every contract assertion. Adding a provider means adding one subject.

Support doubles added to `Support/Stubs.swift`: `SpyHTTPClient` (records URL + headers per
call, returns configured data/status), `StubCodexAuthReader`.

**Registry wiring** (`ProviderRegistryTests`): `makeDefault` returns exactly
`ProviderID.displayOrder` IDs in order, no duplicates; each provider built with a
`notFound` credential double fetches to `.needsSignIn` (proves each reader is wired to the
right provider).

### Layer 2 — Core: models, pipeline, persistence, notifications, formatting

Provider-agnostic. Uses `StubUsageProvider` (returns a fixed snapshot, or throws, or waits
`delay` before returning) so no real provider is involved.

- `UsageBoardTests` — empty board; `replace` inserts in `displayOrder` regardless of call
  order; `replace` overwrites the same provider; `snapshot(for:)`; `tightestLimits` skips
  providers with no limits; `latestFetchedAt`; Codable round-trip; `Equatable`.
- `UsageRefresherTests` — two providers both `.ok` ⇒ both in board; one throws ⇒ that entry
  is `.error("Fetch failed")`, the other is `.ok`; one `.stale` with empty limits and a
  previous good entry ⇒ previous limits and `fetchedAt` kept, new status shown; one slow
  (delay) provider ⇒ the fast one's result is present and total time < sum of delays
  (concurrency); providers not in the input list keep their existing board entry.
- `UsageSnapshotTests` — existing `tightestLimit` tests plus `mergingLastGood`: stale+empty
  with previous good ⇒ merged; stale+empty with previous empty ⇒ self; stale with new
  limits ⇒ self; `.ok` ⇒ self; `.needsSignIn`/`.keychainDenied` ⇒ self (blank on purpose);
  previous of a different provider is ignored.
- `SnapshotStoreTests` — board round-trip with two providers; missing file ⇒ `nil`;
  corrupt file ⇒ `nil`; a legacy `usage_snapshot.json` is ignored; App Group path stays
  opt-in.
- `ThresholdEvaluatorTests` — existing single-provider cases unchanged; new: same limit ID
  on two providers ⇒ two crossings with distinct `provider`; state key format
  `"<provider>#<id>#<threshold>"`; a crossing on one provider does not suppress the other.
- `UsageFormatterTests` — two providers ⇒ `◐42%|⬡52%` (no spaces, `|` separator, display
  order); one provider ⇒ `◐42%`; second provider without limits ⇒ omitted; none ⇒ `◐—`;
  percent is rounded, not truncated (`41.6` ⇒ `42%`).
- `ProviderIDTests` — `displayOrder` is `[.claude, .openai]`; `displayName`, `glyph`,
  `clientName` non-empty for every case; `rawValue` round-trip.
- `UsageLimitTests` / `Severity` — existing, unchanged.

### Layer 3 — Provider-specific

What differs per provider: where credentials live, wire format, and any deliberate
divergence from the other provider. Each provider has the same four files.

**Claude** (existing; kept, small additions)
- `ClaudeCredentialsTests` — Keychain JSON parse, epoch-ms expiry, malformed.
- `ClaudeUsageDTOTests` — fixture `usage_response.json`; `resets_at` fractional seconds.
- `ClaudeUsageMapperTests` — `session`, `weekly_all`, `weekly_scoped` (with/without model
  display name), unknown kind fallback.
- `ClaudeUsageProviderTests` — Claude-only behavior: URL path `api/oauth/usage`; header
  `anthropic-beta: oauth-2025-04-20`; `.accessDenied` ⇒ `.keychainDenied`. (Generic status
  paths move to the contract; duplicates are removed from this file.)
- `KeychainTokenReaderIntegrationTests` — opt-in via `RUN_KEYCHAIN_INTEGRATION_TESTS=1`.

**OpenAI** (new)
- `CodexCredentialsTests` — parse a valid `auth.json` (access token, account id); `tokens`
  null ⇒ `.notFound`; empty `access_token` ⇒ `.notFound`; bad JSON ⇒ `.malformed`; `exp`
  from a synthetic JWT (base64url, no padding) ⇒ correct `Date`; JWT with no `exp` or not a
  JWT ⇒ `expiresAt == nil` and no error.
- `FileCodexAuthReaderTests` — temp dir: missing file ⇒ `.notFound`; valid file ⇒ token;
  `CODEX_HOME` resolution is exercised via the explicit `fileURL` initializer (no env
  mutation in tests).
- `OpenAIUsageDTOTests` — fixture `openai_usage_response.json` (sanitized synthetic, real
  structure); `used_percent` integer decodes to `Double`; `rate_limit: null` decodes;
  unknown extra fields are ignored.
- `OpenAIUsageMapperTests` — primary ⇒ `id "session"`, secondary ⇒ `id "weekly_all"`;
  labels for `18000` ⇒ "Session (5h)", `604800` ⇒ "Weekly", `259200` ⇒ "3-day", `nil` ⇒
  positional fallback; `reset_at` ⇒ `Date`; `nil` window omitted; `nil` rate limit ⇒ `[]`;
  severity from thresholds.
- `OpenAIUsageProviderTests` — OpenAI-only behavior: URL path `backend-api/wham/usage`;
  `ChatGPT-Account-Id` header present when account id known and **absent** when `nil`;
  `.accessDenied`/`.malformed` ⇒ `.error` (deliberate divergence from Claude's
  `.keychainDenied`, because there is no Keychain prompt to grant).
- `CodexAuthIntegrationTests` — opt-in via `RUN_CODEX_INTEGRATION_TESTS=1`: real
  `FileCodexAuthReader` + real `URLSessionHTTPClient` ⇒ status is `.ok` or `.needsSignIn`
  (never `.error`). Skipped by default like the Keychain test.

### Fixtures
- `Tests/UsageCoreTests/Fixtures/usage_response.json` (Claude, existing).
- `Tests/UsageCoreTests/Fixtures/openai_usage_response.json` (new, synthetic numbers, ids
  and email replaced with placeholders).
- `Tests/UsageCoreTests/Fixtures/codex_auth.json` (new, fake tokens; the JWT is built in
  the test from a known payload, not copied from a real file).

### App and widget verification (manual, not unit-tested)
The app target stays thin wiring, so it is verified by build + run:
1. `xcodegen generate && xcodebuild … build` ⇒ `BUILD SUCCEEDED`, 0 warnings.
2. Run the app: menu bar shows `◐NN%|⬡NN%`; dropdown and floating panel show a "Claude"
   section and an "OpenAI" section with status/limit rows; "Updated …" line present.
3. Rename `~/.codex/auth.json` temporarily ⇒ OpenAI section shows "Sign in to Codex CLI
   first." and the label drops to `◐NN%`; restore the file ⇒ next refresh recovers.
4. Widget: build only (unsigned widgets do not register; see STATUS.md §4).

### Exit criteria
- `swift test`: all tests pass, 0 failures; the three opt-in integration tests are skipped
  by default.
- Every contract assertion C1–C9 runs for both providers.
- No fetch, merge, or formatting logic exists outside `UsageCore`.
