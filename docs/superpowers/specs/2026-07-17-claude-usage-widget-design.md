# Claude Usage Widget — Design Spec

**Date:** 2026-07-17
**Status:** Approved (brainstorming) — ready for implementation planning

## Context

The user wants a macOS widget that shows the **current plan-quota usage** of their coding
agent — how much of the Claude subscription quota is left (the 5-hour rolling window and the
weekly limits Claude Code enforces for Pro/Max plans). This is the "how much can I still use
before I'm throttled" view, not token/cost accounting.

Claude is the first provider. The design must accommodate adding **xAI** and **OpenAI** later,
though those expose a different notion of "usage" (API credit/spend rather than a Claude-style
5h + weekly plan quota) — so the internal model is provider-agnostic from day one.

There is no documented public API for subscription-plan quota. Investigation of the local
Claude Code install confirmed the exact mechanism its `/usage` command uses (see Data Source),
so we replicate that call.

## Goals

- Menu bar app showing live plan-quota usage, refreshing every ~60s.
- A WidgetKit widget (desktop / Notification Center) sharing the same data.
- Native notifications when a limit crosses configurable thresholds.
- A provider abstraction so xAI/OpenAI are additive later (no core refactor).

## Non-goals (v1)

- Token/cost accounting or historical charts.
- Cooperative OAuth token refresh (see Token Handling — deferred).
- Mac App Store distribution (sandbox conflicts with reading Claude Code's Keychain item).
- xAI / OpenAI providers implemented (only the abstraction is built now).

## Data Source (verified)

- **Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
  (base overridable via `ANTHROPIC_BASE_URL`)
- **Headers:** `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`,
  `Content-Type: application/json`. (`anthropic-version` unconfirmed for this path; include if
  a 400/426 indicates it's required.)
- **Response:** array of limit entries. Each entry:
  - `kind` — `five_hour` (session limit), `seven_day` (weekly), plus model-scoped
    `seven_day_opus` / `seven_day_sonnet` / `weekly_scoped`, and overage entries.
  - `percent` — utilization, 0–100.
  - `resets_at` — Unix epoch seconds when the window resets.
  - `scope.model.display_name` — present for model-scoped weekly entries.
  - overage/status fields (`isUsingOverage`, `overageStatus`, `status`) — surfaced but not
    central to v1.
- **Token storage:** macOS login Keychain, generic-password item, service
  `Claude Code-credentials`, account = current macOS user. Value is JSON with top-level
  `claudeAiOauth` → `{ accessToken, refreshToken, expiresAt (epoch ms), refreshTokenExpiresAt,
  scopes, subscriptionType, rateLimitTier }`.
- **Refresh (deferred, documented for later):** `POST https://api.anthropic.com/v1/oauth/token`,
  `grant_type=refresh_token`, `client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`.

## Architecture

Single Xcode project, three targets:

1. **Core** (framework / Swift package) — shared by app and widget. No UI.
2. **Menu bar app** — the always-running host; owns fetching, notifications, preferences.
3. **Widget extension** — WidgetKit, read-only consumer of the shared snapshot.

Menu bar app and widget share data through an **App Group** container (the app writes the
latest snapshot; the widget reads it).

### Core components

- `UsageProvider` (protocol): `var id: ProviderID { get }`; `func fetch() async throws -> UsageSnapshot`.
- `ClaudeUsageProvider: UsageProvider` — reads the Keychain token, calls `/api/oauth/usage`,
  maps `kind` entries → `UsageLimit`s.
- `KeychainTokenReader` — reads service `Claude Code-credentials`, parses `claudeAiOauth`,
  returns access token + `expiresAt`. Read-only.
- `UsageSnapshot` — `{ provider: ProviderID, fetchedAt: Date, limits: [UsageLimit], status: FetchStatus }`.
- `UsageLimit` — provider-agnostic: `{ id, label, percentUsed: Double, resetsAt: Date?, severity }`.
  Claude maps `five_hour` → "Session (5h)", `seven_day` → "Weekly", model-scoped → labelled by
  `display_name`. Future credit/spend providers map budget-used → `percentUsed`, cycle end →
  `resetsAt`.
- `FetchStatus` — `.ok`, `.stale(reason)`, `.needsSignIn`, `.keychainDenied`, `.error(message)`.
- `SnapshotStore` — encodes/decodes the latest `UsageSnapshot` to the App Group container
  (shared file or `UserDefaults(suiteName:)`), read by both app and widget.
- `ProviderRegistry` — holds the active providers. v1: `[ClaudeUsageProvider()]`. UI iterates
  generically over providers → limits.

### Menu bar app

- `MenuBarExtra` (SwiftUI). A refresh loop (~60s, plus manual refresh) calls the registry,
  writes each snapshot via `SnapshotStore`, and evaluates notification thresholds.
- **Menu bar label:** the tightest (highest `percentUsed`) limit, compact, e.g. `◐ 62% · 2h14m`.
- **Dropdown:** all limits with bars, percentages, and reset times; manual "Refresh now";
  "Preferences"; status/stale indicator; quit.
- **Preferences:** notification thresholds (default 80% / 95%), refresh interval, launch-at-login.

### Widget

- WidgetKit extension. `TimelineProvider` reads the App Group snapshot and schedules refresh
  ~every 15 min (OS-capped; not continuous — this is why the menu bar app is the live view).
- Small/medium families: bars for Session (5h) + Weekly with reset times. Shows a stale badge
  if the snapshot's `fetchedAt` is old.

### Notifications

- `UserNotifications`. When a limit's `percentUsed` crosses a configured threshold (80% / 95%),
  fire one local notification. **De-dupe:** don't re-fire for the same limit+threshold until the
  window resets (`resetsAt` passes) or usage drops back below the threshold. State tracked per
  `(providerID, limitID, threshold)`.

## Token Handling (decision)

**v1 is read-only.** The app uses the stored access token as-is. If it is expired
(`expiresAt` passed) or the endpoint returns 401, the app surfaces `.stale`/`.needsSignIn`
("open Claude Code to refresh") rather than refreshing.

Rationale: refreshing rotates Claude Code's own refresh token; performing it from a separate
process would invalidate Claude Code's stored credentials and break it. Cooperative refresh
(writing rotated tokens back atomically, or the app owning its own OAuth login) is a documented
**later enhancement**, not v1.

Consequence: if the user hasn't run Claude Code recently and the access token has expired, the
widget shows a stale state until Claude Code refreshes it. Accepted trade-off.

## Distribution

Developer ID signing + notarization, hardened runtime, **non-sandboxed** (sandbox would block
reading another app's Keychain item). The first read of `Claude Code-credentials` triggers a
one-time macOS Keychain permission prompt — the user clicks "Always Allow." Project is
scaffolded now; actual signing/notarization is deferred until building a shareable artifact
(requires the user's Apple Developer account).

## Edge cases

- **No token / item absent** → `.needsSignIn`, UI: "Sign in to Claude Code first."
- **Keychain access denied** → `.keychainDenied`, UI: instructions to grant access.
- **Network error / 401 (no refresh)** → keep last snapshot, mark `.stale`, show badge.
- **Token expired** → `.stale`, prompt to open Claude Code.
- **Unknown `kind` values** → mapped to a generic labelled limit (forward-compatible).

## Testing

- **Core unit tests** against a saved fixture of the real `/usage` JSON:
  - `kind` → `UsageLimit` mapping (including model-scoped and unknown kinds).
  - Tightest-limit selection for the menu bar label.
  - Notification threshold + de-dupe logic (crossing 80/95, reset clears state, drop clears).
  - Stale/`needsSignIn` status derivation from token expiry and HTTP status.
  - `SnapshotStore` round-trip encode/decode.
- UI kept thin; logic lives in Core to keep it testable. A mock `UsageProvider` drives app/widget
  previews and tests without network.

## Future / extensibility

- Add `XAIUsageProvider`, `OpenAIUsageProvider` conforming to `UsageProvider`, registered in
  `ProviderRegistry`; they map credit/spend to `UsageLimit`. No changes to UI or store.
- Cooperative token refresh.
- Historical usage / trends.
