# Desktop Usage Panel — Design Spec

**Date:** 2026-07-18
**Status:** Approved (brainstorming) — ready for implementation planning
**Builds on:** the existing menu bar app + `UsageCore` (see `2026-07-17-claude-usage-widget-design.md`).

## Context
The app currently surfaces Claude plan-quota usage via a menu bar item and a WidgetKit
widget. The WidgetKit widget only appears once the app is signed with the user's Apple
Developer team (App Group provisioning), so in unsigned dev builds the user sees only the menu
bar. The user wants an always-visible **desktop panel** they can see now — an ambient, at-a-glance
card living on the desktop.

## Goal
A small translucent card pinned to the **desktop level** (behind normal windows, visible on all
Spaces) showing Session (5h) + Weekly usage, driven live by the same data as the menu bar.
Draggable, remembers its position, toggled on/off from the menu bar.

## Non-goals
- Not a WidgetKit widget (that already exists). This is an in-process `NSWindow`.
- No App Group, no signing dependency — it works in unsigned dev builds.
- No new provider/usage logic — reuses `UsageViewModel`/`UsageCore` unchanged.

## Behavior
- **Level & spaces:** desktop window level (below app windows, above/around the desktop), so it
  never covers the user's work and doesn't steal focus. Present on every Space, stationary across
  Space switches.
- **Content:** compact card (~220×120) with two `LimitRow`s — **Session (5h)** and **Weekly** —
  each a labeled progress bar with % and reset time. Mirrors the menu bar dropdown. Live-updates
  on the existing ~60s refresh (and on manual refresh) because it observes the same
  `UsageViewModel.snapshot`. Falls back to a short status line for non-`.ok` states / empty limits
  (e.g. "Sign in to Claude Code", "No data").
- **Appearance:** `.ultraThinMaterial` (translucent) rounded-rect background, subtle padding —
  reads as a desktop widget.
- **Dragging:** movable by dragging anywhere on the card (`isMovableByWindowBackground`).
- **Position memory:** the panel's frame origin persists to `UserDefaults` and is restored on
  launch/show.
- **Toggle:** a "Show desktop panel" control in the menu bar dropdown, bound to
  `@AppStorage("showDesktopPanel")`. State restored at launch — if enabled, the panel appears on
  app start.

## Architecture (app target only)
- **`App/DesktopPanelController.swift`** — an `NSObject` manager owning an `NSPanel`
  (style `[.borderless, .nonactivatingPanel]`, `backgroundColor = .clear`, `isOpaque = false`,
  `hasShadow = false`). Configures:
  - `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))` (desktop
    level; tune to sit below normal windows — implementer verifies it renders on the desktop and
    behind app windows).
  - `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.
  - `isMovableByWindowBackground = true`; `hidesOnDeactivate = false`.
  - Hosts `NSHostingView(rootView: DesktopPanelView(viewModel:))`.
  - `show()` / `hide()`; restores origin from `UserDefaults` (keys `desktopPanelOriginX/Y`) and
    saves it on `NSWindow.didMoveNotification`.
- **`App/DesktopPanelView.swift`** — SwiftUI card view taking the shared `UsageViewModel`
  (`@ObservedObject`); renders the two limits via the existing `LimitRow`, plus the fallback
  status line. `.ultraThinMaterial` background, rounded corners, fixed ~220×120 frame.
- **`App/AgentUsageApp.swift`** — instantiate `DesktopPanelController` with the shared
  `viewModel`; drive show/hide from `@AppStorage("showDesktopPanel")` (an `.onChange` + initial
  apply at launch).
- **`App/MenuContentView.swift`** — add a `Toggle("Show desktop panel", isOn: $showDesktopPanel)`
  (`@AppStorage`).

## Reuse
- `UsageViewModel` (shared instance — the panel must use the SAME object the menu bar uses, not a
  new one, so both reflect one refresh loop and one snapshot).
- `LimitRow`, `UsageFormatter` (App target, existing).
- `UsageSnapshot.tightestLimit`, `UsageLimit`, `Severity`, `FetchStatus` (UsageCore, existing).

## Edge cases
- No snapshot yet / loading → "Loading…".
- `snapshot.limits` empty or status not `.ok` → the same status messaging the menu bar uses
  (`needsSignIn` → "Sign in to Claude Code", stale/error → show last-good limits per the existing
  transient-failure preservation, else "No data").
- Panel toggled off → window ordered out (not destroyed); toggled on → ordered back at saved
  origin.
- Multiple displays / origin off-screen after a display change → clamp restored origin to a
  visible screen frame (fall back to a default top-right position if off-screen).

## Testing / verification
AppKit window management + SwiftUI presentation are not unit-testable here. Verification:
- `xcodebuild` BUILD SUCCEEDED (unsigned, `CODE_SIGNING_ALLOWED=NO`).
- `swift test` still 41/2/0 (no `UsageCore` change).
- Manual (works unsigned): toggle it on from the menu bar → a translucent card appears on the
  desktop behind other windows; drag it → it moves; quit & relaunch with the toggle on → it
  reappears at the same spot; usage values match the menu bar and update on Refresh.
