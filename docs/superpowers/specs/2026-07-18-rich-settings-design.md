# Rich Settings + Distribution — Design Spec

**Date:** 2026-07-18
**Status:** Approved (brainstorming) — ready for implementation planning
**Builds on:** existing menu bar app, desktop panel, `UsageCore`.

## Context
The app currently has a single Preferences sheet (warning/critical threshold sliders, refresh
interval, launch-at-login). The user wants a richer settings experience: manage providers
(Claude only today), a notifications on/off toggle, and threshold sliders — in a proper macOS
Settings window. Separately, the user wants to publish the app; the chosen distribution target is
**Developer ID + notarization** (NOT the App Store — see Distribution).

## Feature: Rich Settings

Presentation: a standard macOS **Settings window** (SwiftUI `Settings` scene + `TabView`), opened
from a "Settings…" item via `SettingsLink` (macOS 14+), replacing the current Preferences sheet.
Three tabs:

### General
- Refresh interval slider (existing behavior/keys).
- Launch at login (`SMAppService`, existing).
- "Show desktop panel" toggle (`@AppStorage("showDesktopPanel")`) — mirrored here and in the menu.

### Providers (enable/disable list)
- **Claude** row: on/off toggle `@AppStorage("providerClaudeEnabled")` (default `true`) + a status
  line derived from the latest snapshot (`.ok`/limits → "Connected via Claude Code";
  `.needsSignIn` → "Sign in to Claude Code"; else the status reason).
- **xAI** and **OpenAI** rows: visually present but disabled, labeled "Coming soon."
- Behavior: when Claude is disabled, `UsageViewModel.refresh()` skips the fetch and publishes an
  empty snapshot with a new `FetchStatus.disabled` case; the menu bar shows `◐ —` and the
  panel/menu show a "Claude disabled" state. (With one provider, disabling it blanks the readout —
  the honest meaning of the toggle; the structure supports real per-provider control when
  xAI/OpenAI land.)
- **Minimal `UsageCore` change:** add a `case disabled` to `FetchStatus`. This is the only
  `UsageCore` edit; the compiler-enforced exhaustive `switch`es in `MenuContentView.statusRow` and
  `DesktopPanelView.statusText` are updated to render "Claude disabled". A unit test asserts
  `FetchStatus.disabled` is `Equatable`/`Codable` round-trips (keeps the package's coverage).

### Notifications
- **Enable notifications** master toggle `@AppStorage("notificationsEnabled")` (default `true`).
  `NotificationManager.process()` early-returns when off (no alerts even if thresholds cross).
- Warning % and Critical % sliders (existing `warningThreshold`/`criticalThreshold`, 50–100),
  disabled when the master toggle is off.
- A caption shown when the app is **not team-signed**: "Notifications require signing with a
  Developer team" (they are gated on `isTeamSigned` — see NotificationManager).

### New `@AppStorage` keys
- `notificationsEnabled: Bool = true`
- `providerClaudeEnabled: Bool = true`
(Existing keys `warningThreshold` 80, `criticalThreshold` 95, `refreshInterval` 60,
`showDesktopPanel` false — unchanged.)

### Files
- `App/SettingsView.swift` — `TabView` container + `GeneralSettingsTab`, `ProvidersSettingsTab`,
  `NotificationsSettingsTab` (subviews in the same file for cohesion; they are small).
- `App/AgentUsageApp.swift` — add a `Settings { SettingsView(viewModel: viewModel) }` scene.
- `App/MenuContentView.swift` — replace the Preferences-sheet button with `SettingsLink`
  ("Settings…"); keep the desktop-panel toggle and other items.
- `App/NotificationManager.swift` — honor `notificationsEnabled` (early return when off), in
  addition to the existing `isTeamSigned` gate and `status == .ok` guard.
- `App/UsageViewModel.swift` — honor `providerClaudeEnabled` in `refresh()` (skip fetch + publish a
  disabled state when off).
- Retire `App/PreferencesView.swift` (its controls migrate into the General + Notifications tabs).

### Reuse
- `UsageViewModel` (shared instance — Settings' Providers tab reads its `snapshot` for status).
- `ThresholdEvaluator`, `NotificationState` (UsageCore, existing) — unchanged.
- Only `UsageCore` change is the additive `FetchStatus.disabled` case (above).

### Edge cases
- Master notifications off → no notifications regardless of thresholds; sliders disabled/greyed.
- Claude disabled → no fetch; UI shows a clear disabled state; re-enabling resumes on next refresh.
- Unsigned build → notifications can't fire (existing gate); the Notifications tab shows the
  signing caption so the toggle isn't silently inert.

### Testing
UI + app-layer wiring → build + manual verification (no `UsageCore` change). Verify: Settings
window opens with three tabs; toggling Claude off blanks the readout and on resumes it; master
notification toggle disables the sliders and suppresses alerts; threshold changes persist.

## Distribution (decision): Developer ID + Notarization — NOT App Store

**Why not App Store:** App Store requires the **App Sandbox**. A sandboxed app cannot read another
app's Keychain item (`Claude Code-credentials`), which is this app's sole data source — so the
core feature breaks under sandbox. Additionally, using an undocumented endpoint
(`/api/oauth/usage`) and another app's credentials is a high App Store review-rejection risk.
Therefore the app ships **outside** the App Store.

**Chosen path:** Developer ID Application signing + Apple notarization, distributed as a
notarized/stapled `.app` (optionally in a DMG/zip). Non-sandboxed, hardened runtime; reads the
Keychain with the user's one-time approval; full widget + notifications + App Group function once
signed with the user's team.

**Cost/accounts:** requires the paid **Apple Developer Program ($99/yr)** for the Developer ID
certificate, App Group provisioning, and notarization. (A free Personal Team can sign for local
self-use only, ~weekly cert expiry, and generally cannot use App Groups.)

The concrete enrollment + signing + notarization steps the user performs, and the project changes
to support them, are detailed in the implementation plan's "Distribution" section.
