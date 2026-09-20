# Project Status & Handoff — Claude & OpenAI Usage (macOS)

_Last updated: 2026-09-19. Branch: `claude/openai-subscription-usage-ebfef2`._

A macOS app that shows Claude **and** OpenAI (ChatGPT/Codex) subscription **plan-quota** usage
(5-hour rolling window + weekly limits) — as a menu bar item, a WidgetKit widget, and a
desktop-pinned panel — with threshold notifications. Provider-abstracted for future xAI.

---

## 1. Current state (what's built, on `main`, verified)

| Component | State | Verified |
|---|---|---|
| `UsageCore` Swift package (models, DTO, mapper, provider, keychain reader, notifications logic, snapshot store, registry) | **Done** | `swift test` → **152 passed / 3 skipped / 0 failed (155 executed)** |
| OpenAI provider (Codex `auth.json` reader, wham/usage, DTO, mapper, provider-contract tests) | **Done** | `swift test` → **152 passed / 3 skipped / 0 failed (155 executed)** |
| Menu bar app (AppKit `NSStatusItem` hosting the SwiftUI label (autosave name `Tokens`, default preferred position 120 pt from the right so a crowded bar does not hide it); click opens the menu as a popover; 15-minute refresh (slider 15–60 min), dropdown with limits/reset/refresh) | **Done** | Builds; runs unsigned |
| WidgetKit widget (`AgentUsageWidget`) | **Built (code)** | Builds; **does not register** unsigned (see §4) |
| Desktop panel (pinned NSPanel, draggable, toggle) | **Done** | Builds; runs unsigned; toggle in menu |
| Threshold notifications (80% / 95%, de-duped) | **Built** | Gated off unless team-signed (see §4) |
| Clean build (app + embedded widget) | **Done** | `xcodebuild … BUILD SUCCEEDED`, 0 warnings |

**Everything above is on this branch, pending merge to `main`.** The app currently runs from a local unsigned build
(installed at `~/Applications/AgentUsageApp.app`).

### Data source (verified, undocumented)
`GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer <token>`,
`anthropic-beta: oauth-2025-04-20`. Token read **read-only** from the macOS login Keychain item
`Claude Code-credentials` → `claudeAiOauth.accessToken`. Response is a top-level object whose
`limits` array is the source of truth (kinds `session` / `weekly_all` / `weekly_scoped`;
`resets_at` is an ISO-8601 string). We never write/refresh the token; expired/401 → stale state.
The usage endpoint rate-limits at a few calls per hour and every rejected call counts; the app
honors `Retry-After` per provider and backs off (see the "Rate-limit backoff" section of
`docs/superpowers/specs/2026-09-19-openai-usage-provider-design.md`).

**OpenAI (ChatGPT/Codex):** `GET https://chatgpt.com/backend-api/wham/usage`, headers
`Authorization: Bearer <access_token>` + `ChatGPT-Account-Id: <account_id>`. Credentials read
**read-only** from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`), fields
`tokens.access_token` / `tokens.account_id`; token expiry from the JWT `exp` claim. We never
refresh the token; expired/401 → stale state. Response fields used: `rate_limit.primary_window`
(5h) and `secondary_window` (weekly) — `used_percent`, `limit_window_seconds`, `reset_at`.

---

## 2. Architecture

- **`UsageCore/`** (local SwiftPM package) — all business logic + unit tests. `UsageProvider`
  protocol → `ClaudeUsageProvider`, `OpenAIUsageProvider`; `UsageSnapshot`/`UsageLimit`/`FetchStatus`;
  `UsageBoard` (one snapshot per provider); `UsageRefresher` (concurrent fetch + last-good merge);
  `UsageFormatter` (menu bar label); `ThresholdEvaluator` (+ `NotificationState` dedupe);
  `SnapshotStore` (App Group JSON, now `usage_board.json`); `KeychainTokenReader`;
  `FileCodexAuthReader` (read-only `~/.codex/auth.json`); `ProviderRegistry`.
- **`App/`** — menu bar app (`AgentUsageApp`, `UsageViewModel`, `MenuContentView`+`LimitRow`,
  `ProviderSection`, `MenuBarLabelView`+`UsageFormatter`, `NotificationManager`, `PreferencesView`,
  `DesktopPanelController`+`DesktopPanelView`). The menu renders stacked Claude and
  OpenAI sections via `ProviderSection`; menu bar label is compact multi-provider, e.g. `◐42%|⬡52%` (a provider with no data shows `◐—`).
  A provider with a non-`.ok` status keeps its rows dimmed to 40 % with the status text centered on top, no background.
  The floating panel is a 72-pt-wide vertical strip, one thin bar per provider (tightest limit, tick for the other window), percent above, glyph and data age below, hover for the full breakdown; stale/rate-limited providers get a frosted glass with a status icon.
  Thin wiring over `UsageCore`.
- **`Widget/`** — `AgentUsageWidget` extension (TimelineProvider reads the App Group snapshot).
- **`project.yml`** — XcodeGen source of truth → generates `AgentUsage.xcodeproj` (git-ignored).
  Bundle IDs `com.gilad.agentusage` / `.widget`; App Group `group.com.gilad.agentusage`;
  non-sandboxed, hardened runtime.

---

## 3. Build / run / test

```bash
# Unit tests (fast, no Xcode):
swift test                          # 152 passed / 3 skipped / 0 failed (155 executed)
#   opt-in integration tests (need a real keychain / entitlement / Codex auth file; hang or prompt otherwise):
#   RUN_KEYCHAIN_INTEGRATION_TESTS=1   RUN_APP_GROUP_INTEGRATION_TESTS=1   RUN_CODEX_INTEGRATION_TESTS=1

# App build (unsigned, local):
xcodegen generate
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# Run it (menu bar + desktop panel work unsigned):
open build/Build/Products/Debug/AgentUsageApp.app
#   → approve the one-time Keychain prompt; menu bar shows "◐NN%|⬡NN%";
#     toggle "Show desktop panel" for the desktop card.
```
**Process hygiene:** run ONE `xcodebuild`/`swift test` at a time. If a build/app hangs, `pkill -9 -f xcodebuild` / `pkill -x AgentUsageApp`. (A concurrent-build pileup and a wedged `SWBBuildService` daemon each caused silent hangs during development — see §6.)

---

## 4. The signing wall (what needs your Apple Developer team)

The app runs unsigned, but three things **require signing with your paid Apple Developer team**
(empirically confirmed — ad-hoc is NOT enough):

1. **WidgetKit widget in the OS widget gallery** — macOS refuses to register an ad-hoc/unsigned
   widget extension (`pluginkit` won't add it). Needs a Developer-team signature.
2. **Threshold notifications** — `UNUserNotificationCenter.current()` aborts in an unsigned app;
   `NotificationManager` is gated on `isTeamSigned` and skips notifications otherwise.
3. **App Group live data sharing** (app↔widget snapshot) — the group container is provisioned only
   with the paid team.

The menu bar app + desktop panel do **not** need signing.

**App Store is NOT viable** for this app: it mandates the App Sandbox, and a sandboxed app cannot
read Claude Code's Keychain token (the whole data source); plus the undocumented endpoint +
cross-app-credential use is a high review-rejection risk. Distribution path is **Developer ID +
notarization** (outside the App Store).

---

## 5. Pending actions

### A. Publish to GitHub (private, under gilador84) — YOU run
`gh` is installed but authed as the **work** account `a work account`; the repo must go under the
**personal** account. Not yet pushed. To push `main`:
```bash
# create an empty PRIVATE repo at https://github.com/new (under gilador84), then:
git remote add origin git@github.com:gilador84/claude-usage-widget.git   # confirm username/name
GIT_SSH_COMMAND='ssh -i ~/.ssh/id_rsa-personal' git push -u origin main
# (or: gh auth login as gilador84 → gh auth switch --user gilador84 → gh repo create … --push)
```

### B. Developer ID signing + notarization — runbook ready
See `docs/superpowers/plans/2026-07-18-rich-settings.md` → "Publishing: Developer ID +
Notarization". `[USER]` steps: enroll ($99/yr), add Apple ID in Xcode, get your 10-char **Team
ID**, create a *Developer ID Application* cert, set up `notarytool` credentials. Then hand me the
**Team ID** and I wire `project.yml`; you run archive → export → notarize → staple.

### C. Parked feature: Rich Settings — designed, NOT implemented
Tabbed Settings window (General / Providers enable-disable / Notifications toggle + thresholds).
- Spec: `docs/superpowers/specs/2026-07-18-rich-settings-design.md`
- Plan (4 tasks, complete code): `docs/superpowers/plans/2026-07-18-rich-settings.md`
- To resume: execute that plan via `superpowers:subagent-driven-development`. Tasks need no
  signing; task 1 adds `FetchStatus.disabled` to `UsageCore` (TDD), tasks 2–4 are the UI + wiring.

---

## 6. Gotchas / lessons (so the next session doesn't relearn them)

- **Unsigned builds must not touch the App Group container.** On this macOS, opening a file in `~/Library/Group Containers/group.com.gilad.agentusage/` from an unsigned process blocks on a privacy prompt (it hung the app at launch with a locked screen). The app stores its board in `~/Library/Application Support/Tokens/` unless team-signed (`StorageLocation`). The widget still reads the group container, which only works signed.
- **`swift test` can hang** on integration tests that touch real system services: the Keychain
  reader test and the App Group container test are **env-gated** (opt-in via
  `RUN_KEYCHAIN_INTEGRATION_TESTS` / `RUN_APP_GROUP_INTEGRATION_TESTS`) precisely because
  `SecItemCopyMatching` and `containerURL(forSecurityApplicationGroupIdentifier:)` block/prompt in
  an unentitled `xctest` process. Default `swift test` skips them.
- **Concurrent builds deadlock.** Launching multiple `swift test`/`xcodebuild` at once creates a
  SwiftPM lock pileup; and a wedged `SWBBuildService` daemon makes builds hang with no output.
  Fix: `pkill` the strays / `pkill -9 -f SWBBuildService` (it respawns), one build at a time.
- **Unsigned launch crash (fixed):** `UNUserNotificationCenter.current()` aborts unsigned →
  `NotificationManager` now no-ops unless `isTeamSigned`.
- **The committed test fixture** (`Tests/UsageCoreTests/Fixtures/usage_response.json`) is
  **sanitized synthetic** data with the real structure — not real usage numbers.

---

## 7. Doc index
- Specs: `docs/superpowers/specs/2026-07-17-claude-usage-widget-design.md`,
  `…/2026-07-18-desktop-usage-panel-design.md`, `…/2026-07-18-rich-settings-design.md`,
  `…/2026-09-19-openai-usage-provider-design.md`
- Plans: `docs/superpowers/plans/2026-07-17-claude-usage-widget.md`,
  `…/2026-07-18-desktop-usage-panel.md`, `…/2026-07-18-rich-settings.md`,
  `…/2026-09-19-openai-usage-provider.md`
- SDD progress ledger (git-ignored scratch): `.superpowers/sdd/progress.md`
