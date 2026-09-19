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
`usage_board.json`. The single-snapshot API and `usage_snapshot.json` are removed. No
migration: the first refresh runs at launch.

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

**`UsageFormatter.compactLabel(for board: UsageBoard) -> String`** (moved from the app):
joins `"<glyph><percent>%"` per provider in `tightestLimits` with `"·"`, no spaces, e.g.
`◐42%·⬡52%`. Providers with no limits are omitted. Empty → `◐—`.

### App

- **`UsageViewModel`**: `@Published var board = UsageBoard()`; loads the stored board at
  init. `refresh()` runs every provider concurrently (`withTaskGroup`), a thrown fetch
  becomes `.error("Fetch failed")` for that provider, applies `mergingLastGood` against the
  current board entry, replaces it in the board, saves, calls `notifications.process(board)`,
  reloads widget timelines. Registry gets `FileCodexAuthReader()` and the `CHATGPT_BASE_URL`
  override.
- **`MenuContentView`** and **`DesktopPanelView`**: `ForEach(board.snapshots)` renders a
  `ProviderSection` (shared view, `App/ProviderSection.swift`): header
  `Text(provider.displayName).font(.caption.bold())`, status row, then `LimitRow`s, or
  "No usage data." when `.ok` with no limits. Status text is provider-aware:
  `.needsSignIn` → "Sign in to \(clientName) first."; `.keychainDenied` text unchanged.
  Sections separated by a thin `Divider`. One "Updated …" line at the bottom from
  `board.latestFetchedAt`. Panel title "Agent Usage"; quit alert "Quit Agent Usage?".
  Loading state ("Loading…") when the board is empty.
- **`MenuBarLabelView`**: `Text(UsageFormatter.compactLabel(for: board))`.
- **`NotificationManager.process(_ board:)`**: for each snapshot with `.ok`, run the
  evaluator with the shared `NotificationState`; title
  `"\(provider.displayName) \(limit.label) at NN%"`. Team-signed gate unchanged.

### Widget

- `UsageEntry.board: UsageBoard?`; provider reads `store.load()`.
- `.systemMedium`: for each provider in the board, a header line and the `session` /
  `weekly_all` rows. `.systemSmall`: one row per provider showing the tightest limit.
- Display name and description: "Agent Usage" / "Plan-quota usage for Claude and OpenAI."
- Stale marker: `latestFetchedAt` older than 30 min.

## Out of scope

Per-provider enable/disable in Settings (parked in the rich-settings spec), token refresh,
credits, `additional_rate_limits`, model availability, xAI.

## Testing

`UsageCore` (TDD, `swift test`):
- `UsageBoardTests`: order, replace, tightest per provider, latest fetched, Codable round-trip.
- `CodexCredentialsTests`: parse valid file, `tokens` null → notFound, bad JSON → malformed,
  `exp` decoding with a synthetic JWT, bad JWT → nil expiry.
- `FileCodexAuthReaderTests`: missing file → notFound (temp dir).
- `OpenAIUsageDTOTests`: decode fixture `Tests/UsageCoreTests/Fixtures/openai_usage_response.json`
  (sanitized synthetic, real structure); `rate_limit: null`.
- `OpenAIUsageMapperTests`: IDs, labels for 18000/604800/other/nil, resets, severity, nil → [].
- `OpenAIUsageProviderTests`: each status path with stub reader + stub HTTP client;
  headers include bearer + account id; account id omitted when nil.
- `UsageSnapshotTests`: `mergingLastGood` cases.
- `ThresholdEvaluatorTests`: same limit ID on two providers fires twice; key format.
- `UsageFormatterTests`: two providers, one provider, none.
- `ProviderRegistryTests`: two providers, order.
- `SnapshotStoreTests`: board round-trip.

App/widget: `xcodegen generate` + `xcodebuild … build` with 0 warnings; run the app and
confirm both sections and the two-number label. Widget: build only (unsigned cannot register).
