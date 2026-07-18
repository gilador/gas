# Desktop Usage Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible, desktop-pinned translucent card showing Session (5h) + Weekly usage, driven by the existing `UsageViewModel`, draggable with remembered position, toggled from the menu bar.

**Architecture:** App-target-only. A `DesktopPanelController` owns an `NSPanel` at desktop window level hosting a SwiftUI `DesktopPanelView` bound to the SAME `UsageViewModel` instance the menu bar uses. Visibility is driven by `@AppStorage("showDesktopPanel")`, applied at launch and on change. No `UsageCore` changes, no App Group, no signing dependency — it runs in unsigned dev builds.

**Tech Stack:** AppKit (`NSPanel`, `NSHostingView`), SwiftUI, `@AppStorage`/`UserDefaults`. macOS 14, Swift 5.9. No third-party deps.

## Global Constraints
- macOS 14.0; Swift 5.9; no third-party deps.
- App target only (`App/`). Do NOT modify `UsageCore`, `project.yml`, entitlements, or the widget.
- The panel MUST observe the SAME `UsageViewModel` instance as the menu bar (one refresh loop, one snapshot) — never create a second `UsageViewModel`.
- Reuse the existing `LimitRow` (in `App/MenuContentView.swift`) and `UsageCore` types (`UsageSnapshot`, `UsageLimit`, `FetchStatus`). Limit ids are `"session"` and `"weekly_all"` (real mapper output).
- Card size ~220×120; `.ultraThinMaterial` rounded background; desktop window level; present on all Spaces; draggable; origin persisted to `UserDefaults` keys `desktopPanelOriginX`/`desktopPanelOriginY`; visibility in `@AppStorage("showDesktopPanel")` (default false).
- Build verification uses the unsigned command: `xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`.
- Process hygiene: run ONE build/launch at a time; if a build/launch hangs >90s, `pkill -9 -f xcodebuild` / `pkill -x AgentUsageApp` and investigate — never pile up concurrent builds.
- Conventional Commits (`feat:`), no ticket ref.

---

### Task 1: DesktopPanelView + DesktopPanelController

**Files:**
- Create: `App/DesktopPanelView.swift`
- Create: `App/DesktopPanelController.swift`

**Interfaces:**
- Consumes: `UsageViewModel` (App), `LimitRow` (App/MenuContentView.swift), `UsageSnapshot`/`UsageLimit`/`FetchStatus` (UsageCore).
- Produces: `struct DesktopPanelView: View { init(viewModel: UsageViewModel) }`; `@MainActor final class DesktopPanelController { var viewModel: UsageViewModel?; func show(); func hide() }`.

**Steps:**

- [ ] **Step 1: Create `App/DesktopPanelView.swift`**
```swift
import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Usage").font(.caption.bold())
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 220, height: 120, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            let shown = displayLimits(snapshot)
            if shown.isEmpty {
                Text(statusText(snapshot.status)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(shown) { LimitRow(limit: $0) }
            }
        } else {
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func displayLimits(_ s: UsageSnapshot) -> [UsageLimit] {
        let session = s.limits.first { $0.id == "session" }
        let weekly = s.limits.first { $0.id == "weekly_all" }
        return [session, weekly].compactMap { $0 }
    }

    private func statusText(_ status: FetchStatus) -> String {
        switch status {
        case .ok: return "No data"
        case .stale(let reason): return reason
        case .needsSignIn: return "Sign in to Claude Code"
        case .keychainDenied: return "Keychain access denied"
        case .error(let message): return message
        }
    }
}
```

- [ ] **Step 2: Create `App/DesktopPanelController.swift`**
```swift
import AppKit
import SwiftUI

@MainActor
final class DesktopPanelController {
    var viewModel: UsageViewModel?

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private static let size = NSSize(width: 220, height: 120)
    private static let originXKey = "desktopPanelOriginX"
    private static let originYKey = "desktopPanelOriginY"

    func show() {
        guard let viewModel else { return }
        if panel == nil { panel = makePanel(viewModel: viewModel) }
        guard let panel else { return }
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(viewModel: UsageViewModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false

        let host = NSHostingView(rootView: DesktopPanelView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let moved = note.object as? NSWindow else { return }
            let origin = moved.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: Self.originXKey)
            UserDefaults.standard.set(Double(origin.y), forKey: Self.originYKey)
        }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.originXKey) != nil,
           defaults.object(forKey: Self.originYKey) != nil {
            let origin = NSPoint(x: defaults.double(forKey: Self.originXKey),
                                 y: defaults.double(forKey: Self.originYKey))
            panel.setFrameOrigin(clampedOrigin(origin))
        } else {
            panel.setFrameOrigin(defaultOrigin())
        }
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let rect = NSRect(origin: origin, size: Self.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
            return origin
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: vf.maxX - Self.size.width - 20,
                       y: vf.maxY - Self.size.height - 20)
    }
}
```

- [ ] **Step 3: Build (unsigned) — expect BUILD SUCCEEDED**
Run:
```bash
cd /Users/user/dev/personal/tokens && xcodegen generate
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Expected: `** BUILD SUCCEEDED **` (the new files compile; not yet wired into the app).

- [ ] **Step 4: Confirm the package is untouched — expect 41/2/0**
Run: `swift test` → `Executed 41 tests, with 2 tests skipped and 0 failures`.

- [ ] **Step 5: Commit**
```bash
git add App/DesktopPanelView.swift App/DesktopPanelController.swift
git commit -m "feat: add desktop panel view and NSPanel controller"
```

---

### Task 2: Wire the panel into the app + menu toggle

**Files:**
- Modify: `App/AgentUsageApp.swift`
- Modify: `App/MenuContentView.swift`

**Interfaces:**
- Consumes: `DesktopPanelController`, `UsageViewModel` (Task 1 / existing).
- Produces: no new public types; adds a `@State DesktopPanelController` wired to `@AppStorage("showDesktopPanel")` in `AgentUsageApp`, and a `Toggle` in `MenuContentView`.

**Steps:**

- [ ] **Step 1: Replace `App/AgentUsageApp.swift`**
```swift
import SwiftUI

@main
struct AgentUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false
    @State private var panelController = DesktopPanelController()

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
    }

    private func applyPanelVisibility() {
        if showDesktopPanel {
            panelController.show()
        } else {
            panelController.hide()
        }
    }
}
```
> Note: the `MenuBarExtra` label view renders as soon as the menu bar item appears at launch, so `.onAppear` reliably wires the controller and applies the persisted visibility on startup.

- [ ] **Step 2: Add the toggle to `App/MenuContentView.swift`**
In `MenuContentView`, add an `@AppStorage` property alongside the existing `@State`:
```swift
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false
```
and insert a toggle in the `VStack` between the "Refresh now" and "Preferences…" buttons:
```swift
                Toggle("Show desktop panel", isOn: $showDesktopPanel)
```

- [ ] **Step 3: Regenerate + build (unsigned) — expect BUILD SUCCEEDED**
```bash
cd /Users/user/dev/personal/tokens && xcodegen generate
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

- [ ] **Step 4: Confirm package still green — expect 41/2/0**
Run: `swift test`.

- [ ] **Step 5: Launch smoke (must stay alive, no crash)**
```bash
pkill -x AgentUsageApp 2>/dev/null
open build/Build/Products/Debug/AgentUsageApp.app   # build path from the derivedDataPath used at launch
pgrep -x AgentUsageApp && echo ALIVE || echo CRASHED
```
Expected: `ALIVE`. (Leave it running for manual inspection; do not kill on success.)

- [ ] **Step 6: Commit**
```bash
git add App/AgentUsageApp.swift App/MenuContentView.swift
git commit -m "feat: wire desktop panel toggle into app and menu bar"
```

---

## Manual verification (user, works unsigned)
- Open the menu bar dropdown → toggle **Show desktop panel** on → a translucent card appears on the desktop (behind other windows), showing Session (5h) + Weekly bars matching the menu bar.
- Drag the card → it moves; quit and relaunch (toggle still on) → it reappears at the same position.
- Toggle off → the card disappears; on → reappears.
- Values update on the ~60s refresh and on **Refresh now**.

## Self-review (completed by plan author)
- **Spec coverage:** desktop-level pinned NSPanel (T1 controller), all-Spaces + stationary + draggable (T1 collectionBehavior/isMovableByWindowBackground), compact card with Session+Weekly via LimitRow (T1 view), position persistence + off-screen clamp (T1), shared viewModel (T2 sets `panelController.viewModel = viewModel`), toggle + restore-at-launch (T2 AppStorage + onAppear/onChange), status/loading fallbacks (T1 statusText), unsigned-friendly build + manual steps (both tasks). All spec sections mapped.
- **Placeholder scan:** every code step is complete Swift; no TODO/ambiguous steps.
- **Type consistency:** `DesktopPanelController.viewModel`, `.show()`, `.hide()`, `DesktopPanelView(viewModel:)`, and the `@AppStorage("showDesktopPanel")` key/`UserDefaults` origin keys are identical across Tasks 1 and 2.
