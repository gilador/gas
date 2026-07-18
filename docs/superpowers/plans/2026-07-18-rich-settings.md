# Rich Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single Preferences sheet with a proper macOS Settings window (three tabs: General, Providers, Notifications), add a notifications on/off master toggle and a per-provider Claude enable/disable toggle, and add the one supporting `UsageCore` change (`FetchStatus.disabled`). Then document the Developer ID + notarization publishing runbook.

**Architecture:** Menu bar app (`MenuBarExtra`, `.window` style) + widget extension, backed by a shared `UsageCore` Swift package. A single `UsageViewModel` (`@MainActor`, `ObservableObject`) owns fetch/refresh, the `NotificationManager`, and the `SnapshotStore`. Settings is a SwiftUI `Settings` scene containing a `TabView`; each tab reads/writes `@AppStorage` keys, and the Providers tab reads the live `viewModel.snapshot`. Provider enable/disable and notification enable/disable are enforced in the app layer (`UsageViewModel.refresh()` and `NotificationManager.process()`), not in `UsageCore`.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14 deployment target, XcodeGen (`project.yml` → `AgentUsage.xcodeproj`), Swift Package Manager for `UsageCore` (unit tests via XCTest). `SMAppService` for launch-at-login, `UserNotifications` for alerts, `WidgetKit` for the widget.

## Global Constraints

- **Platform:** macOS 14.0 minimum (`SettingsLink` requires macOS 14+; already the deployment target).
- **Language:** Swift 5.9 (`SWIFT_VERSION` in `project.yml`).
- **Scope of changes:** App-target-only, EXCEPT one additive change in `UsageCore` — adding `case disabled` to `FetchStatus`. No other `UsageCore` edits.
- **`@AppStorage` keys + defaults (exact):**
  - New: `notificationsEnabled: Bool = true`, `providerClaudeEnabled: Bool = true`.
  - Existing (unchanged): `warningThreshold = 80.0` (range 50...100, step 1), `criticalThreshold = 95.0` (range 50...100, step 1), `refreshInterval = 60.0` (range 30...300, step 10), `showDesktopPanel = false`.
- **Build command (app, no signing):**
  ```
  xcodegen generate
  xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  ```
  Expect `** BUILD SUCCEEDED **`. Run `xcodegen generate` before each app build (the `.xcodeproj` is generated, not committed source of truth).
- **Package test command:** `swift test` (or `swift test --filter UsageSnapshotTests` for the TDD loop).
- **Process hygiene:** one build/test at a time; if a build or launched app hangs > 90s, `pkill -x xcodebuild` and/or `pkill -x AgentUsageApp` before retrying. Only one `xcodebuild` process at a time.
- **Commits:** Conventional Commits, no ticket prefix (e.g. `feat: add rich settings window`). One commit per task.
- **Verification honesty:** The `UsageCore` task has a real automated unit test. All UI/wiring tasks are verified by **build + launch-smoke** only; the visual/interaction check (window opens, tabs switch, toggles behave) is the **user's** manual step — label it as such and do not claim it as automated.

---

### Task 1: UsageCore — add `FetchStatus.disabled` (TDD)

Add the additive enum case that represents "provider intentionally turned off", with a unit test proving `Equatable` + `Codable` round-trip. Then fix the compiler-forced exhaustive switches in the app target so both the package and the app compile.

**Files**
- Modify: `Sources/UsageCore/Models/UsageSnapshot.swift`
- Test: `Tests/UsageCoreTests/UsageSnapshotTests.swift`
- Modify (app-target, for exhaustiveness): `App/MenuContentView.swift`, `App/DesktopPanelView.swift`, `App/UsageViewModel.swift`

**Interfaces**
- Produces: `FetchStatus.disabled` (a new case on `public enum FetchStatus: Codable, Sendable, Equatable`).
- Consumes: nothing new.
- Note: `Widget/UsageWidgetView.swift` does NOT switch on `FetchStatus` (it branches on `snapshot.limits.isEmpty`), so **no widget change is required.** The only other `switch` over a value named `status` is in `Sources/UsageCore/Keychain/KeychainTokenReader.swift`, which switches on `OSStatus`, not `FetchStatus` — leave it untouched.

**Steps**

1. - [ ] Write the failing test. Append to `Tests/UsageCoreTests/UsageSnapshotTests.swift` (inside the existing `final class UsageSnapshotTests: XCTestCase`, after `testFetchStatusEquatable`):
   ```swift
   func testFetchStatusDisabledEquatableAndCodableRoundTrip() throws {
       XCTAssertEqual(FetchStatus.disabled, .disabled)
       XCTAssertNotEqual(FetchStatus.disabled, .ok)
       XCTAssertNotEqual(FetchStatus.disabled, .needsSignIn)
       let encoded = try JSONEncoder().encode(FetchStatus.disabled)
       let decoded = try JSONDecoder().decode(FetchStatus.self, from: encoded)
       XCTAssertEqual(decoded, .disabled)
   }
   ```
2. - [ ] Run `swift test --filter UsageSnapshotTests` and confirm it FAILS to compile (`type 'FetchStatus' has no member 'disabled'`). This proves the test exercises the new case.
3. - [ ] Add the case. In `Sources/UsageCore/Models/UsageSnapshot.swift`, change the enum to:
   ```swift
   public enum FetchStatus: Codable, Sendable, Equatable {
       case ok
       case stale(reason: String)
       case needsSignIn
       case keychainDenied
       case error(message: String)
       case disabled
   }
   ```
4. - [ ] Run `swift test --filter UsageSnapshotTests` and confirm it PASSES.
5. - [ ] Run the full package suite `swift test` and confirm the result: expect **42 tests, 2 skipped, 0 failed** (41 existing + 1 new; the 2 skips are the Keychain integration tests that no-op without a live keychain item). If the skip count differs on this machine, the pass/fail line must still show `0 failed`.
6. - [ ] Fix the app-target exhaustive switches (the package now compiles, but the app will not until these are updated). In `App/MenuContentView.swift`, add a `case` to `statusRow(_:)` before the closing brace of the `switch`:
   ```swift
   case .disabled:
       Label("Claude disabled", systemImage: "pause.circle")
           .foregroundStyle(.secondary)
   ```
7. - [ ] In `App/DesktopPanelView.swift`, add a `case` to `statusText(_:)`:
   ```swift
   case .disabled: return "Claude disabled"
   ```
8. - [ ] In `App/UsageViewModel.swift`, the `switch fetched.status` in `refresh()` is exhaustive and must handle the new case. Add `.disabled` to the pass-through arm so it reads:
   ```swift
   case .ok, .needsSignIn, .keychainDenied, .disabled:
       snap = fetched
   ```
   (A provider fetch never returns `.disabled` today, but the compiler requires the case; the real disabled behavior is wired in Task 4.)
9. - [ ] Build the app to confirm exhaustiveness is satisfied:
   ```
   xcodegen generate
   xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
   Expect `** BUILD SUCCEEDED **`.
10. - [ ] Commit: `feat(core): add FetchStatus.disabled case`

---

### Task 2: Add `SettingsView.swift` (TabView + three tab subviews)

Create the new Settings UI as a single cohesive file: a `TabView` container plus three small tab subviews. This task only ADDS the file; wiring it into the app and retiring the old sheet happens in Task 3. It must build (the file compiles as part of the app target) but is not yet reachable from the UI.

**Files**
- Create: `App/SettingsView.swift`

**Interfaces**
- Consumes: `UsageViewModel` (shared instance, passed in); `@AppStorage` keys `refreshInterval`, `showDesktopPanel`, `providerClaudeEnabled`, `notificationsEnabled`, `warningThreshold`, `criticalThreshold`; `SMAppService.mainApp`; `NotificationManager.isTeamSigned` (made internal in Task 4 — see note below); `viewModel.snapshot` and `FetchStatus`.
- Produces: `struct SettingsView`, `struct GeneralSettingsTab`, `struct ProvidersSettingsTab`, `struct NotificationsSettingsTab`.
- **Ordering note:** `NotificationsSettingsTab` references `NotificationManager.isTeamSigned`, which is `private static` today and becomes `internal static` in Task 4. To keep this task independently build-verifiable, perform the one-line visibility change (`private static var isTeamSigned` → `static var isTeamSigned`) in `App/NotificationManager.swift` **as the first step of this task**; Task 4 then adds the behavior around it. This is the single dependency crossing task boundaries — do it here so Task 2 compiles.

**Steps**

1. - [ ] In `App/NotificationManager.swift`, change the declaration `private static var isTeamSigned: Bool {` to `static var isTeamSigned: Bool {` (drop `private`). No other change in this task.
2. - [ ] Create `App/SettingsView.swift` with the complete contents:
   ```swift
   import SwiftUI
   import ServiceManagement
   import UsageCore

   struct SettingsView: View {
       @ObservedObject var viewModel: UsageViewModel

       var body: some View {
           TabView {
               GeneralSettingsTab(viewModel: viewModel)
                   .tabItem { Label("General", systemImage: "gearshape") }
               ProvidersSettingsTab(viewModel: viewModel)
                   .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
               NotificationsSettingsTab()
                   .tabItem { Label("Notifications", systemImage: "bell") }
           }
           .frame(width: 440, height: 320)
       }
   }

   struct GeneralSettingsTab: View {
       @ObservedObject var viewModel: UsageViewModel
       @AppStorage("refreshInterval") private var refreshInterval = 60.0
       @AppStorage("showDesktopPanel") private var showDesktopPanel = false
       @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

       var body: some View {
           Form {
               Section("Refresh") {
                   HStack {
                       Text("Interval (s)")
                       Slider(value: $refreshInterval, in: 30...300, step: 10)
                       Text("\(Int(refreshInterval))")
                   }
               }
               Section {
                   Toggle("Launch at login", isOn: $launchAtLogin)
                       .onChange(of: launchAtLogin) { _, enabled in
                           try? (enabled ? SMAppService.mainApp.register()
                                         : SMAppService.mainApp.unregister())
                       }
                   Toggle("Show desktop panel", isOn: $showDesktopPanel)
               }
           }
           .formStyle(.grouped)
           .padding(20)
           .onChange(of: refreshInterval) { _, newValue in
               viewModel.refreshInterval = newValue
               viewModel.start()
           }
       }
   }

   struct ProvidersSettingsTab: View {
       @ObservedObject var viewModel: UsageViewModel
       @AppStorage("providerClaudeEnabled") private var providerClaudeEnabled = true

       var body: some View {
           Form {
               Section("Providers") {
                   Toggle(isOn: $providerClaudeEnabled) {
                       VStack(alignment: .leading, spacing: 2) {
                           Text("Claude")
                           Text(claudeStatus)
                               .font(.caption)
                               .foregroundStyle(.secondary)
                       }
                   }
                   comingSoonRow("xAI")
                   comingSoonRow("OpenAI")
               }
           }
           .formStyle(.grouped)
           .padding(20)
       }

       private var claudeStatus: String {
           guard providerClaudeEnabled else { return "Disabled" }
           guard let snapshot = viewModel.snapshot else { return "Loading…" }
           if snapshot.status == .ok || !snapshot.limits.isEmpty {
               return "Connected via Claude Code"
           }
           switch snapshot.status {
           case .ok:
               return "Connected via Claude Code"
           case .needsSignIn:
               return "Sign in to Claude Code"
           case .disabled:
               return "Disabled"
           case .stale(let reason):
               return reason
           case .keychainDenied:
               return "Keychain access denied"
           case .error(let message):
               return message
           }
       }

       private func comingSoonRow(_ name: String) -> some View {
           Toggle(isOn: .constant(false)) {
               VStack(alignment: .leading, spacing: 2) {
                   Text(name)
                   Text("Coming soon")
                       .font(.caption)
                       .foregroundStyle(.secondary)
               }
           }
           .disabled(true)
       }
   }

   struct NotificationsSettingsTab: View {
       @AppStorage("notificationsEnabled") private var notificationsEnabled = true
       @AppStorage("warningThreshold") private var warningThreshold = 80.0
       @AppStorage("criticalThreshold") private var criticalThreshold = 95.0

       var body: some View {
           Form {
               Section {
                   Toggle("Enable notifications", isOn: $notificationsEnabled)
               }
               Section("Thresholds") {
                   HStack {
                       Text("Warning %")
                       Slider(value: $warningThreshold, in: 50...100, step: 1)
                       Text("\(Int(warningThreshold))")
                   }
                   HStack {
                       Text("Critical %")
                       Slider(value: $criticalThreshold, in: 50...100, step: 1)
                       Text("\(Int(criticalThreshold))")
                   }
               }
               .disabled(!notificationsEnabled)
               if !NotificationManager.isTeamSigned {
                   Section {
                       Text("Notifications require signing with a Developer team.")
                           .font(.caption)
                           .foregroundStyle(.secondary)
                   }
               }
           }
           .formStyle(.grouped)
           .padding(20)
       }
   }
   ```
3. - [ ] Build:
   ```
   xcodegen generate
   xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
   Expect `** BUILD SUCCEEDED **`. (The new views compile but are not yet presented — that is Task 3.)
4. - [ ] Commit: `feat: add tabbed SettingsView (General/Providers/Notifications)`

---

### Task 3: Wire the Settings scene + `SettingsLink`, retire `PreferencesView`

Add the `Settings` scene to the app, replace the Preferences sheet button in the menu with a `SettingsLink`, and delete `App/PreferencesView.swift`. Verified by build + launch-smoke.

**Files**
- Modify: `App/AgentUsageApp.swift`
- Modify: `App/MenuContentView.swift`
- Delete: `App/PreferencesView.swift`

**Interfaces**
- Consumes: `SettingsView(viewModel:)` (from Task 2), `SettingsLink` (macOS 14+), the shared `viewModel`.
- Produces: a `Settings` scene; a "Settings…" menu item that opens the standard Settings window.

**Steps**

1. - [ ] In `App/AgentUsageApp.swift`, add a `Settings` scene after the `MenuBarExtra`. Replace the whole `body` with:
   ```swift
   var body: some Scene {
       MenuBarExtra {
           MenuContentView(viewModel: viewModel)
       } label: {
           MenuBarLabelView(snapshot: viewModel.snapshot)
               .onAppear {
                   panelController.viewModel = viewModel
                   applyPanelVisibility()
               }
               .onChange(of: showDesktopPanel) { _, _ in
                   applyPanelVisibility()
               }
       }
       .menuBarExtraStyle(.window)

       Settings {
           SettingsView(viewModel: viewModel)
       }
   }
   ```
2. - [ ] In `App/MenuContentView.swift`, remove the `@State private var showingPreferences = false` line.
3. - [ ] In `App/MenuContentView.swift`, replace the button line:
   ```swift
   Button("Preferences…") { showingPreferences = true }
   ```
   with:
   ```swift
   SettingsLink {
       Text("Settings…")
   }
   ```
4. - [ ] In `App/MenuContentView.swift`, remove the trailing sheet modifier so the `body` ends at the `.frame(width: 280)` line:
   ```swift
           .padding(12)
           .frame(width: 280)
       }
   ```
   (Delete the entire `.sheet(isPresented: $showingPreferences) { PreferencesView(viewModel: viewModel) }` block.)
5. - [ ] Delete `App/PreferencesView.swift` (`rm App/PreferencesView.swift`). Its controls now live in `GeneralSettingsTab` (refresh interval, launch at login) and `NotificationsSettingsTab` (warning/critical sliders).
6. - [ ] Build:
   ```
   xcodegen generate
   xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
   Expect `** BUILD SUCCEEDED **`.
7. - [ ] Launch-smoke (build + manual): locate the built product and open it, then confirm the process is alive:
   ```
   APP=$(xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' -showBuildSettings CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)/AgentUsageApp.app
   open "$APP"
   sleep 3 && pgrep -x AgentUsageApp && echo ALIVE || echo DEAD
   ```
   Expect `ALIVE`. Then `pkill -x AgentUsageApp` to clean up.
8. - [ ] **User manual check (not automated):** click the menu bar icon → "Settings…" opens the standard macOS Settings window with three tabs (General, Providers, Notifications) that switch correctly, and the menu no longer shows "Preferences…".
9. - [ ] Commit: `feat: open Settings via SettingsLink; retire PreferencesView`

---

### Task 4: Behavior wiring — honor `notificationsEnabled` and `providerClaudeEnabled`

Make the toggles functional. `NotificationManager.process()` early-returns when notifications are disabled; `UsageViewModel.refresh()` skips the fetch and publishes a `.disabled` snapshot when Claude is disabled (and does NOT run notifications for it). The `isTeamSigned` visibility change was already made in Task 2.

**Files**
- Modify: `App/NotificationManager.swift`
- Modify: `App/UsageViewModel.swift`

**Interfaces**
- Consumes: `UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true`; `UserDefaults.standard.object(forKey: "providerClaudeEnabled") as? Bool ?? true`; `FetchStatus.disabled` (Task 1); `UsageSnapshot(provider:fetchedAt:limits:status:)`.
- Produces: gated notification behavior; a `.disabled` snapshot path in `refresh()`.

**Steps**

1. - [ ] In `App/NotificationManager.swift`, add the `notificationsEnabled` gate to `process(_:)`. Replace the two existing guards at the top of the method:
   ```swift
   func process(_ snapshot: UsageSnapshot) {
       guard let center else { return }
       guard snapshot.status == .ok else { return }
   ```
   with:
   ```swift
   func process(_ snapshot: UsageSnapshot) {
       guard let center else { return }
       let notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
       guard notificationsEnabled else { return }
       guard snapshot.status == .ok else { return }
   ```
   (`defaults` is the existing `private let defaults = UserDefaults.standard`.)
2. - [ ] In `App/UsageViewModel.swift`, add the provider-disabled short-circuit at the top of `refresh()`. Replace:
   ```swift
   func refresh() async {
       guard let provider = registry.providers.first else { return }
   ```
   with:
   ```swift
   func refresh() async {
       let claudeEnabled = UserDefaults.standard.object(forKey: "providerClaudeEnabled") as? Bool ?? true
       guard claudeEnabled else {
           let disabled = UsageSnapshot(provider: .claude, fetchedAt: Date(),
                                        limits: [], status: .disabled)
           self.snapshot = disabled
           try? store.save(disabled)
           WidgetCenter.shared.reloadAllTimelines()
           return
       }
       guard let provider = registry.providers.first else { return }
   ```
   Note: this path deliberately does NOT call `notifications.process(_:)` — a disabled provider produces no alerts. It still saves + reloads the widget timeline, matching the normal path.
3. - [ ] Build:
   ```
   xcodegen generate
   xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
   Expect `** BUILD SUCCEEDED **`.
4. - [ ] Launch-smoke (build + manual), same as Task 3 step 7. Expect `ALIVE`, then `pkill -x AgentUsageApp`.
5. - [ ] **User manual check (not automated):** In Settings → Providers, toggle Claude OFF → the menu bar readout blanks (`◐ —`) and the menu/panel show "Claude disabled"; toggle ON → data resumes on the next refresh. In Settings → Notifications, turning the master toggle OFF greys the two sliders and suppresses alerts even when a threshold is crossed. Threshold changes persist across relaunch.
6. - [ ] Commit: `feat: honor notificationsEnabled and providerClaudeEnabled toggles`

---

## Publishing: Developer ID + Notarization

This section is a **runbook**, not a coding task. Per the spec, the app ships **outside the App Store** (Developer ID Application signing + Apple notarization), because the App Store mandates the App Sandbox and a sandboxed app cannot read Claude Code's Keychain credential — the app's sole data source. The app is **non-sandboxed** (no `com.apple.security.app-sandbox` entitlement), uses the hardened runtime, and both the app and its embedded widget extension must be Developer-ID signed and notarized.

Two streams below: **[USER]** steps are performed by the user outside the agent (they need the paid account, signing identity, and notarization credentials the agent does not have). **[AGENT]** steps are config edits the agent can make once the user supplies the Team ID.

### Stream 1 — [USER] one-time account + credential setup

1. **[USER] Enroll in the Apple Developer Program ($99/yr).** Go to https://developer.apple.com/programs/ and enroll. Developer ID certificates, App Group provisioning, and notarization all require the paid program — a free Personal Team can only sign for local self-use (certs expire ~weekly and it generally cannot use App Groups).
2. **[USER] Add the Apple ID in Xcode.** Xcode → Settings → Accounts → "+" → Apple ID → sign in. Confirm the paid team appears under the account (not just a "Personal Team").
3. **[USER] Find the 10-character Team ID.** https://developer.apple.com → Account → Membership details → "Team ID" (10 alphanumeric chars, e.g. `A1B2C3D4E5`). Also visible in Xcode → Settings → Accounts → select team → the ID in parentheses.
4. **[USER] Create a "Developer ID Application" certificate.** Easiest: Xcode → Settings → Accounts → select team → "Manage Certificates…" → "+" → **Developer ID Application**. (Manual alternative: https://developer.apple.com → Certificates → "+" → Developer ID Application, then download and double-click to install into the login keychain.) Confirm it is in the login keychain: `security find-identity -v -p codesigning` should list a `Developer ID Application: <name> (<TEAMID>)` identity.
5. **[USER] Set up notarytool credentials.** Store a reusable keychain profile so later `notarytool` calls just reference it. Pick ONE of:
   - **App Store Connect API key (recommended):** create a key at https://appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API. Then:
     ```
     xcrun notarytool store-credentials "AgentUsageNotary" \
       --key /path/to/AuthKey_XXXXXXXXXX.p8 \
       --key-id XXXXXXXXXX \
       --issuer aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
     ```
   - **Apple ID + app-specific password:** create an app-specific password at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords. Then:
     ```
     xcrun notarytool store-credentials "AgentUsageNotary" \
       --apple-id "gilador84@gmail.com" \
       --team-id <TEAMID> \
       --password <app-specific-password>
     ```
   Either form creates the keychain profile named `AgentUsageNotary` used in Stream 3.
6. **[USER] Provide the Team ID to the agent** so it can wire `project.yml` (Stream 2).

### Stream 2 — [AGENT] project config changes (after receiving Team ID)

7. **[AGENT] Set signing settings in `project.yml`.** These currently read `CODE_SIGN_IDENTITY: "-"` (ad-hoc) for both targets. For Developer-ID release signing, set (for BOTH `AgentUsageApp` and `AgentUsageWidget` targets):
   - `DEVELOPMENT_TEAM: <TEAMID>`
   - `CODE_SIGN_STYLE: Automatic` (already set)
   - `CODE_SIGN_IDENTITY: "Developer ID Application"` (for the Release configuration)
   - `ENABLE_HARDENED_RUNTIME: YES` (already set — keep it)

   Recommended: scope the Developer-ID identity to Release only via `project.yml` per-configuration settings, keeping `"-"` for Debug so local unsigned builds still work. Example shape for each target's `settings`:
   ```yaml
   settings:
     base:
       PRODUCT_BUNDLE_IDENTIFIER: com.gilad.agentusage
       INFOPLIST_FILE: App/Info.plist
       CODE_SIGN_ENTITLEMENTS: App/AgentUsageApp.entitlements
       CODE_SIGN_STYLE: Automatic
       DEVELOPMENT_TEAM: <TEAMID>
       ENABLE_HARDENED_RUNTIME: YES
       MARKETING_VERSION: "0.1.0"
       CURRENT_PROJECT_VERSION: "1"
       SWIFT_VERSION: "5.9"
     configs:
       Debug:
         CODE_SIGN_IDENTITY: "-"
       Release:
         CODE_SIGN_IDENTITY: "Developer ID Application"
   ```
   Then run `xcodegen generate`.
8. **[AGENT] Review entitlements.** Both `App/AgentUsageApp.entitlements` and `Widget/AgentUsageWidget.entitlements` declare only `com.apple.security.application-groups` = `group.com.gilad.agentusage`. Keep them as-is. **Do NOT add `com.apple.security.app-sandbox`** — the app must remain non-sandboxed to read the Keychain. The App Group is provisioned automatically by automatic signing once the paid team is set (App Groups require the paid program).

### Stream 3 — [USER] build, notarize, staple

These run on the user's machine; they need the Developer-ID signing identity in the keychain and the `AgentUsageNotary` notarization profile (Stream 1), plus network access. The agent cannot run them.

9. **[USER] Archive:**
   ```
   xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp \
     -configuration Release -derivedDataPath build \
     -archivePath build/AgentUsage.xcarchive archive
   ```
10. **[USER] Create `ExportOptions.plist`** (Developer-ID export) at the repo root:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>method</key>
        <string>developer-id</string>
        <key>teamID</key>
        <string>TEAMID</string>
        <key>signingStyle</key>
        <string>automatic</string>
    </dict>
    </plist>
    ```
    (Replace `TEAMID`.)
11. **[USER] Export the signed `.app`:**
    ```
    xcodebuild -exportArchive \
      -archivePath build/AgentUsage.xcarchive \
      -exportPath build/export \
      -exportOptionsPlist ExportOptions.plist
    ```
12. **[USER] Zip for submission:**
    ```
    ditto -c -k --keepParent build/export/AgentUsageApp.app build/export/AgentUsageApp.app.zip
    ```
13. **[USER] Submit to notarization and wait:**
    ```
    xcrun notarytool submit build/export/AgentUsageApp.app.zip \
      --keychain-profile "AgentUsageNotary" --wait
    ```
    Expect `status: Accepted`. On `Invalid`, fetch the log with `xcrun notarytool log <submission-id> --keychain-profile "AgentUsageNotary"`.
14. **[USER] Staple the ticket to the `.app`** (staple the app bundle, not the zip):
    ```
    xcrun stapler staple build/export/AgentUsageApp.app
    ```
15. **[USER] Verify signature + Gatekeeper acceptance:**
    ```
    codesign --verify --deep --strict --verbose=2 build/export/AgentUsageApp.app
    spctl -a -vvv --type execute build/export/AgentUsageApp.app
    ```
    Expect `codesign` to report valid, and `spctl` to report `accepted` / `source=Notarized Developer ID`.

### Gotchas

- **Both binaries must be signed + notarized.** The embedded widget extension (`AgentUsageWidget.appex`) inside the `.app` must carry the same Developer-ID signature; `-exportArchive` handles this when both targets have the Team ID set. Notarization covers the whole bundle (app + appex).
- **App Group works once the paid team provisions it.** With automatic signing and the Team ID set, the `group.com.gilad.agentusage` App Group provisions automatically; a free Personal Team generally cannot, which is another reason the paid program is required.
- **End users still get a one-time Keychain prompt.** Notarization removes the Gatekeeper "unidentified developer" block, but the first time the app reads Claude Code's Keychain item, macOS shows the user a one-time Keychain-access approval prompt. This is expected and unavoidable for cross-app Keychain reads; it is not a signing failure.
