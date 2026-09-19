# OpenAI (Codex) Usage Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show ChatGPT/Codex subscription usage next to Claude usage in the menu bar, dropdown, floating panel, and widget, with threshold notifications for both.

**Architecture:** `UsageCore` gains a `UsageBoard` (one snapshot per provider), a `UsageRefresher` pipeline, and an `OpenAIUsageProvider` that mirrors `ClaudeUsageProvider` (read-only credential reader → GET usage → DTO → mapper). The app and widget become thin renderers of the board. Every core change is test-first.

**Tech Stack:** Swift 5.9 language mode on the Swift 6.3 toolchain, SwiftPM (`swift test`), XCTest, SwiftUI/AppKit, WidgetKit, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-19-openai-usage-provider-design.md`

## Global Constraints

- Run ONE `swift test` / `xcodebuild` at a time (concurrent builds deadlock; see STATUS.md §6).
- Credentials are read-only. Never write, refresh, or log a token. Never commit real tokens, ids, or emails; fixtures are synthetic.
- No fetch, merge, or formatting logic outside `UsageCore`. The app and widget only render.
- Code comments: none unless the WHY is non-obvious; one line max; never reference this task or plan.
- Commit after every green task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Test filter syntax: `swift test --filter <TestClassName>`.
- Baseline before Task 1: `swift test` → 41 passed, 2 skipped, 0 failed.

## File Structure

Create (UsageCore):
- `Sources/UsageCore/Models/UsageBoard.swift` — board + `ProviderLimit`.
- `Sources/UsageCore/UsageRefresher.swift` — concurrent fetch + last-good merge.
- `Sources/UsageCore/Formatting/UsageFormatter.swift` — menu bar label.
- `Sources/UsageCore/Keychain/CodexAuthReader.swift` — `CodexAuth`, protocol, `FileCodexAuthReader`.
- `Sources/UsageCore/Keychain/CodexCredentials.swift` — auth.json parse + JWT `exp`.
- `Sources/UsageCore/Providers/OpenAI/OpenAIUsageDTO.swift`
- `Sources/UsageCore/Providers/OpenAI/OpenAIUsageMapper.swift`
- `Sources/UsageCore/Providers/OpenAI/OpenAIUsageProvider.swift`

Modify (UsageCore): `Models/ProviderID.swift`, `Models/UsageSnapshot.swift`, `Notifications/ThresholdEvaluator.swift`, `Store/SnapshotStore.swift`, `ProviderRegistry.swift`.

Create (tests): `UsageBoardTests`, `UsageRefresherTests`, `UsageFormatterTests`, `ProviderIDTests`, `CodexCredentialsTests`, `FileCodexAuthReaderTests`, `OpenAIUsageDTOTests`, `OpenAIUsageMapperTests`, `OpenAIUsageProviderTests`, `Contract/UsageProviderContract.swift`, `ClaudeUsageProviderContractTests`, `OpenAIUsageProviderContractTests`, `CodexAuthIntegrationTests`, fixtures `openai_usage_response.json`, `codex_auth.json`.

Modify (tests): `Support/Stubs.swift`, `UsageSnapshotTests`, `ThresholdEvaluatorTests`, `SnapshotStoreTests`, `ProviderRegistryTests`, `ClaudeUsageProviderTests`.

App: create `App/ProviderSection.swift`; modify `UsageViewModel`, `MenuBarLabelView`, `MenuContentView`, `DesktopPanelView`, `NotificationManager`. Widget: modify `AgentUsageWidget.swift`, `UsageWidgetView.swift`. Docs: `STATUS.md`.

---

### Task 1: `ProviderID` display metadata

**Files:**
- Modify: `Sources/UsageCore/Models/ProviderID.swift`
- Test: `Tests/UsageCoreTests/ProviderIDTests.swift`

**Interfaces:**
- Produces: `ProviderID.displayOrder: [ProviderID]`, `displayName`, `glyph`, `clientName` (all `String`), `CaseIterable`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/UsageCoreTests/ProviderIDTests.swift
import XCTest
@testable import UsageCore

final class ProviderIDTests: XCTestCase {
    func testDisplayOrderIsClaudeThenOpenAI() {
        XCTAssertEqual(ProviderID.displayOrder, [.claude, .openai])
    }

    func testDisplayNames() {
        XCTAssertEqual(ProviderID.claude.displayName, "Claude")
        XCTAssertEqual(ProviderID.openai.displayName, "OpenAI")
        XCTAssertEqual(ProviderID.xai.displayName, "xAI")
    }

    func testGlyphs() {
        XCTAssertEqual(ProviderID.claude.glyph, "◐")
        XCTAssertEqual(ProviderID.openai.glyph, "⬡")
    }

    func testClientNames() {
        XCTAssertEqual(ProviderID.claude.clientName, "Claude Code")
        XCTAssertEqual(ProviderID.openai.clientName, "Codex CLI")
    }

    func testEveryCaseHasNonEmptyMetadata() {
        for id in ProviderID.allCases {
            XCTAssertFalse(id.displayName.isEmpty, "\(id)")
            XCTAssertFalse(id.glyph.isEmpty, "\(id)")
            XCTAssertFalse(id.clientName.isEmpty, "\(id)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderIDTests`
Expected: compile error, `displayOrder` / `displayName` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Models/ProviderID.swift
public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case claude
    case xai
    case openai

    public static let displayOrder: [ProviderID] = [.claude, .openai]

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .xai: return "xAI"
        }
    }

    public var glyph: String {
        switch self {
        case .claude: return "◐"
        case .openai: return "⬡"
        case .xai: return "✕"
        }
    }

    public var clientName: String {
        switch self {
        case .claude: return "Claude Code"
        case .openai: return "Codex CLI"
        case .xai: return "xAI"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProviderIDTests`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Models/ProviderID.swift Tests/UsageCoreTests/ProviderIDTests.swift
git commit -m "feat(core): ProviderID display order, names, glyphs

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `UsageBoard` model

**Files:**
- Create: `Sources/UsageCore/Models/UsageBoard.swift`
- Modify: `Sources/UsageCore/Models/UsageSnapshot.swift` (add `Equatable`)
- Test: `Tests/UsageCoreTests/UsageBoardTests.swift`

**Interfaces:**
- Consumes: `ProviderID.displayOrder` (Task 1).
- Produces:
  ```swift
  public struct ProviderLimit: Equatable, Sendable { let provider: ProviderID; let limit: UsageLimit }
  public struct UsageBoard: Codable, Sendable, Equatable {
      public private(set) var snapshots: [UsageSnapshot]
      public init(snapshots: [UsageSnapshot] = [])
      public var isEmpty: Bool
      public func snapshot(for: ProviderID) -> UsageSnapshot?
      public mutating func replace(_ snapshot: UsageSnapshot)
      public var tightestLimits: [ProviderLimit]
      public var latestFetchedAt: Date?
  }
  ```

- [ ] **Step 1: Write the failing test**

```swift
// Tests/UsageCoreTests/UsageBoardTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class UsageBoardTests: XCTestCase {
    private func limit(_ id: String, _ pct: Double) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct, resetsAt: nil, severity: .normal)
    }
    private func snap(_ provider: ProviderID, limits: [UsageLimit] = [],
                      fetchedAt: TimeInterval = 0, status: FetchStatus = .ok) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testEmptyBoard() {
        let board = UsageBoard()
        XCTAssertTrue(board.isEmpty)
        XCTAssertTrue(board.snapshots.isEmpty)
        XCTAssertNil(board.snapshot(for: .claude))
        XCTAssertTrue(board.tightestLimits.isEmpty)
        XCTAssertNil(board.latestFetchedAt)
    }

    func testReplaceKeepsDisplayOrderRegardlessOfInsertOrder() {
        var board = UsageBoard()
        board.replace(snap(.openai))
        board.replace(snap(.claude))
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
        XCTAssertFalse(board.isEmpty)
    }

    func testInitSortsSnapshots() {
        let board = UsageBoard(snapshots: [snap(.openai), snap(.claude)])
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
    }

    func testReplaceOverwritesSameProvider() {
        var board = UsageBoard(snapshots: [snap(.claude, fetchedAt: 1)])
        board.replace(snap(.claude, fetchedAt: 2))
        XCTAssertEqual(board.snapshots.count, 1)
        XCTAssertEqual(board.snapshot(for: .claude)?.fetchedAt, Date(timeIntervalSince1970: 2))
    }

    func testSnapshotForProvider() {
        let board = UsageBoard(snapshots: [snap(.claude), snap(.openai, fetchedAt: 9)])
        XCTAssertEqual(board.snapshot(for: .openai)?.fetchedAt, Date(timeIntervalSince1970: 9))
        XCTAssertNil(board.snapshot(for: .xai))
    }

    func testTightestLimitsOnePerProviderSkippingEmpty() {
        let board = UsageBoard(snapshots: [
            snap(.claude, limits: [limit("session", 40), limit("weekly_all", 88)]),
            snap(.openai, status: .needsSignIn)
        ])
        XCTAssertEqual(board.tightestLimits,
                       [ProviderLimit(provider: .claude, limit: limit("weekly_all", 88))])
    }

    func testTightestLimitsFollowsDisplayOrder() {
        let board = UsageBoard(snapshots: [
            snap(.openai, limits: [limit("session", 52)]),
            snap(.claude, limits: [limit("session", 42)])
        ])
        XCTAssertEqual(board.tightestLimits.map(\.provider), [.claude, .openai])
    }

    func testLatestFetchedAtIsNewest() {
        let board = UsageBoard(snapshots: [snap(.claude, fetchedAt: 100), snap(.openai, fetchedAt: 300)])
        XCTAssertEqual(board.latestFetchedAt, Date(timeIntervalSince1970: 300))
    }

    func testCodableRoundTrip() throws {
        let board = UsageBoard(snapshots: [
            snap(.claude, limits: [limit("session", 40)], fetchedAt: 5),
            snap(.openai, fetchedAt: 6, status: .stale(reason: "x"))
        ])
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(UsageBoard.self, from: data)
        XCTAssertEqual(decoded, board)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageBoardTests`
Expected: compile error, `UsageBoard` not found.

- [ ] **Step 3: Write minimal implementation**

Add `Equatable` to `UsageSnapshot`:

```swift
// Sources/UsageCore/Models/UsageSnapshot.swift — change the declaration line only
public struct UsageSnapshot: Codable, Sendable, Equatable {
```

```swift
// Sources/UsageCore/Models/UsageBoard.swift
import Foundation

public struct ProviderLimit: Equatable, Sendable {
    public let provider: ProviderID
    public let limit: UsageLimit

    public init(provider: ProviderID, limit: UsageLimit) {
        self.provider = provider
        self.limit = limit
    }
}

public struct UsageBoard: Codable, Sendable, Equatable {
    public private(set) var snapshots: [UsageSnapshot]

    public init(snapshots: [UsageSnapshot] = []) {
        self.snapshots = []
        for snapshot in snapshots { replace(snapshot) }
    }

    public var isEmpty: Bool { snapshots.isEmpty }

    public func snapshot(for provider: ProviderID) -> UsageSnapshot? {
        snapshots.first { $0.provider == provider }
    }

    public mutating func replace(_ snapshot: UsageSnapshot) {
        snapshots.removeAll { $0.provider == snapshot.provider }
        snapshots.append(snapshot)
        snapshots.sort { Self.rank($0.provider) < Self.rank($1.provider) }
    }

    public var tightestLimits: [ProviderLimit] {
        snapshots.compactMap { snapshot in
            snapshot.tightestLimit.map { ProviderLimit(provider: snapshot.provider, limit: $0) }
        }
    }

    public var latestFetchedAt: Date? {
        snapshots.map(\.fetchedAt).max()
    }

    private static func rank(_ provider: ProviderID) -> Int {
        ProviderID.displayOrder.firstIndex(of: provider) ?? Int.max
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageBoardTests`
Expected: 9 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Models/UsageBoard.swift Sources/UsageCore/Models/UsageSnapshot.swift Tests/UsageCoreTests/UsageBoardTests.swift
git commit -m "feat(core): UsageBoard holds one snapshot per provider

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Last-good merge on `UsageSnapshot`

**Files:**
- Modify: `Sources/UsageCore/Models/UsageSnapshot.swift`
- Test: `Tests/UsageCoreTests/UsageSnapshotTests.swift`

**Interfaces:**
- Produces: `UsageSnapshot.mergingLastGood(previous: UsageSnapshot?) -> UsageSnapshot`.

- [ ] **Step 1: Write the failing tests** (append inside the existing `UsageSnapshotTests` class)

```swift
    private func snap(_ provider: ProviderID = .claude, limits: [UsageLimit],
                      fetchedAt: TimeInterval, status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testMergeStaleEmptyKeepsPreviousLimitsAndTimestamp() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "offline"))
        let merged = fetched.mergingLastGood(previous: previous)
        XCTAssertEqual(merged.limits, previous.limits)
        XCTAssertEqual(merged.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(merged.status, .stale(reason: "offline"))
    }

    func testMergeErrorEmptyKeepsPreviousLimits() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .error(message: "HTTP 500"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous).limits, previous.limits)
    }

    func testMergeStaleWithPreviousEmptyReturnsSelf() {
        let previous = snap(limits: [], fetchedAt: 100, status: .needsSignIn)
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeStaleWithNewLimitsReturnsSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [limit("session", 50)], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeOkReturnsSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .ok)
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeNeedsSignInAndKeychainDeniedReturnSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        for status in [FetchStatus.needsSignIn, .keychainDenied] {
            let fetched = snap(limits: [], fetchedAt: 200, status: status)
            XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
        }
    }

    func testMergeIgnoresPreviousOfOtherProvider() {
        let previous = snap(.openai, limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(.claude, limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeWithNilPreviousReturnsSelf() {
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: nil), fetched)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageSnapshotTests`
Expected: compile error, `mergingLastGood` not found.

- [ ] **Step 3: Write minimal implementation** (append inside `UsageSnapshot`)

```swift
    /// Keeps the previous good limits (and their timestamp) when a refresh fails transiently.
    public func mergingLastGood(previous: UsageSnapshot?) -> UsageSnapshot {
        guard let previous, previous.provider == provider,
              !previous.limits.isEmpty, limits.isEmpty else { return self }
        switch status {
        case .stale, .error:
            return UsageSnapshot(provider: provider, fetchedAt: previous.fetchedAt,
                                 limits: previous.limits, status: status)
        case .ok, .needsSignIn, .keychainDenied:
            return self
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageSnapshotTests`
Expected: 11 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Models/UsageSnapshot.swift Tests/UsageCoreTests/UsageSnapshotTests.swift
git commit -m "feat(core): UsageSnapshot.mergingLastGood

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Provider-aware `ThresholdEvaluator`

**Files:**
- Modify: `Sources/UsageCore/Notifications/ThresholdEvaluator.swift`
- Test: `Tests/UsageCoreTests/ThresholdEvaluatorTests.swift`

**Interfaces:**
- Produces: `ThresholdCrossing(provider: ProviderID, limit: UsageLimit, threshold: Double)`; state key `"<provider.rawValue>#<limit.id>#<threshold>"`.

- [ ] **Step 1: Write the failing tests**

Change the existing helper to accept a provider, and add three tests:

```swift
    private func snap(_ limits: [UsageLimit], provider: ProviderID = .claude) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(), limits: limits, status: .ok)
    }

    func testSameLimitIDOnTwoProvidersFiresTwice() {
        var state = NotificationState()
        let claude = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .claude),
                                                 state: &state, thresholds: [80])
        let openai = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai),
                                                 state: &state, thresholds: [80])
        XCTAssertEqual(claude.count, 1)
        XCTAssertEqual(openai.count, 1)
        XCTAssertEqual(claude.first?.provider, .claude)
        XCTAssertEqual(openai.first?.provider, .openai)
    }

    func testStateKeyIncludesProvider() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai), state: &state, thresholds: [80])
        XCTAssertEqual(Array(state.fired.keys), ["openai#five_hour#80.0"])
    }

    func testOneProviderDroppingDoesNotClearTheOther() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .claude), state: &state, thresholds: [80])
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai), state: &state, thresholds: [80])
        _ = ThresholdEvaluator.evaluate(snap([limit(10)], provider: .openai), state: &state, thresholds: [80])
        let claudeAgain = ThresholdEvaluator.evaluate(snap([limit(85)], provider: .claude),
                                                      state: &state, thresholds: [80])
        XCTAssertTrue(claudeAgain.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThresholdEvaluatorTests`
Expected: compile error, `ThresholdCrossing` has no member `provider`; key test would fail.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Notifications/ThresholdEvaluator.swift — replace ThresholdCrossing and the key line
public struct ThresholdCrossing: Equatable, Sendable {
    public let provider: ProviderID
    public let limit: UsageLimit
    public let threshold: Double

    public init(provider: ProviderID, limit: UsageLimit, threshold: Double) {
        self.provider = provider
        self.limit = limit
        self.threshold = threshold
    }
}
```

Inside `evaluate`, change:

```swift
                let key = "\(snapshot.provider.rawValue)#\(limit.id)#\(threshold)"
                if limit.percentUsed >= threshold {
                    if state.fired[key] != window {
                        crossings.append(ThresholdCrossing(provider: snapshot.provider,
                                                           limit: limit, threshold: threshold))
                        state.fired[key] = window
                    }
```

Also update the `NotificationState.fired` doc line to: `/// key: "<provider>#<limitID>#<threshold>" -> resetsAt (epoch seconds, 0 if none) it last fired for.`

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ThresholdEvaluatorTests`
Expected: 9 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Notifications/ThresholdEvaluator.swift Tests/UsageCoreTests/ThresholdEvaluatorTests.swift
git commit -m "feat(core): provider-scoped threshold de-dupe keys

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `UsageFormatter` in core

**Files:**
- Create: `Sources/UsageCore/Formatting/UsageFormatter.swift`
- Test: `Tests/UsageCoreTests/UsageFormatterTests.swift`

**Interfaces:**
- Consumes: `UsageBoard.tightestLimits`, `ProviderID.glyph`.
- Produces: `public enum UsageFormatter { public static func compactLabel(for board: UsageBoard) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/UsageCoreTests/UsageFormatterTests.swift
import XCTest
@testable import UsageCore

final class UsageFormatterTests: XCTestCase {
    private func snap(_ provider: ProviderID, _ pcts: [Double], status: FetchStatus = .ok) -> UsageSnapshot {
        let limits = pcts.enumerated().map { i, p in
            UsageLimit(id: "l\(i)", label: "l\(i)", percentUsed: p, resetsAt: nil, severity: .normal)
        }
        return UsageSnapshot(provider: provider, fetchedAt: Date(), limits: limits, status: status)
    }

    func testTwoProvidersCompactNoSpaces() {
        let board = UsageBoard(snapshots: [snap(.claude, [12, 42]), snap(.openai, [52, 7])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%·⬡52%")
    }

    func testOneProvider() {
        let board = UsageBoard(snapshots: [snap(.claude, [42])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%")
    }

    func testProviderWithoutLimitsIsOmitted() {
        let board = UsageBoard(snapshots: [snap(.claude, [42]), snap(.openai, [], status: .needsSignIn)])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%")
    }

    func testEmptyBoardShowsDash() {
        XCTAssertEqual(UsageFormatter.compactLabel(for: UsageBoard()), "◐—")
    }

    func testPercentIsRoundedNotTruncated() {
        let board = UsageBoard(snapshots: [snap(.claude, [41.6])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageFormatterTests`
Expected: compile error, `UsageFormatter` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Formatting/UsageFormatter.swift
public enum UsageFormatter {
    public static func compactLabel(for board: UsageBoard) -> String {
        let parts = board.tightestLimits.map {
            "\($0.provider.glyph)\(Int($0.limit.percentUsed.rounded()))%"
        }
        return parts.isEmpty ? "◐—" : parts.joined(separator: "·")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageFormatterTests`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Formatting/UsageFormatter.swift Tests/UsageCoreTests/UsageFormatterTests.swift
git commit -m "feat(core): compact multi-provider menu bar label formatter

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `SnapshotStore` persists a board

**Files:**
- Modify: `Sources/UsageCore/Store/SnapshotStore.swift`
- Test: `Tests/UsageCoreTests/SnapshotStoreTests.swift`

**Interfaces:**
- Produces: `SnapshotStore.save(_ board: UsageBoard) throws`, `SnapshotStore.load() -> UsageBoard?`. The single-snapshot API is removed.

- [ ] **Step 1: Write the failing tests** — replace `testRoundTrip` and add two tests; keep `testLoadReturnsNilWhenMissing` and the opt-in App Group test unchanged.

```swift
    private func limit(_ id: String, _ pct: Double) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct,
                   resetsAt: Date(timeIntervalSince1970: 1000), severity: .normal)
    }

    func testBoardRoundTrip() throws {
        let store = SnapshotStore(containerURL: try tempDir())
        let board = UsageBoard(snapshots: [
            UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                          limits: [limit("session", 42)], status: .ok),
            UsageSnapshot(provider: .openai, fetchedAt: Date(timeIntervalSince1970: 600),
                          limits: [], status: .stale(reason: "offline"))
        ])
        try store.save(board)
        XCTAssertEqual(store.load(), board)
    }

    func testCorruptFileLoadsNil() throws {
        let dir = try tempDir()
        try "not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("usage_board.json"))
        XCTAssertNil(SnapshotStore(containerURL: dir).load())
    }

    func testLegacySingleSnapshotFileIsIgnored() throws {
        let dir = try tempDir()
        let legacy = UsageSnapshot(provider: .claude, fetchedAt: Date(), limits: [], status: .ok)
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("usage_snapshot.json"))
        XCTAssertNil(SnapshotStore(containerURL: dir).load())
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SnapshotStoreTests`
Expected: compile error, `save` expects `UsageSnapshot`, `load()` returns `UsageSnapshot?`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Store/SnapshotStore.swift — replace the file
import Foundation

public struct SnapshotStore {
    private let fileURL: URL

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("usage_board.json")
    }

    public init(appGroupID: String) {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.temporaryDirectory.appendingPathComponent(appGroupID, isDirectory: true)
        try? fm.createDirectory(at: container, withIntermediateDirectories: true)
        self.init(containerURL: container)
    }

    public func save(_ board: UsageBoard) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(board)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> UsageBoard? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageBoard.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SnapshotStoreTests`
Expected: 4 tests run, 0 failures, 1 skipped (App Group).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Store/SnapshotStore.swift Tests/UsageCoreTests/SnapshotStoreTests.swift
git commit -m "feat(core): SnapshotStore persists a UsageBoard

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Test doubles + `UsageRefresher`

**Files:**
- Modify: `Tests/UsageCoreTests/Support/Stubs.swift`
- Create: `Sources/UsageCore/UsageRefresher.swift`
- Test: `Tests/UsageCoreTests/UsageRefresherTests.swift`

**Interfaces:**
- Consumes: `UsageBoard.replace/snapshot(for:)`, `UsageSnapshot.mergingLastGood`.
- Produces: `public enum UsageRefresher { public static func refresh(_ board: UsageBoard, providers: [any UsageProvider]) async -> UsageBoard }`; doubles `SpyHTTPClient`, `StubUsageProvider`, `StubError`.

- [ ] **Step 1: Add the doubles** (append to `Tests/UsageCoreTests/Support/Stubs.swift`)

```swift
struct StubError: Error {}

/// Records every request; returns the configured body and status.
final class SpyHTTPClient: UsageHTTPClient, @unchecked Sendable {
    struct Call { let url: URL; let headers: [String: String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    let data: Data
    let statusCode: Int
    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); _calls.append(Call(url: url, headers: headers)); lock.unlock()
        let resp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

struct StubUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let result: Result<UsageSnapshot, Error>
    var delay: TimeInterval = 0
    func fetch() async throws -> UsageSnapshot {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try result.get()
    }
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/UsageCoreTests/UsageRefresherTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class UsageRefresherTests: XCTestCase {
    private func limit(_ pct: Double) -> UsageLimit {
        UsageLimit(id: "session", label: "Session", percentUsed: pct, resetsAt: nil, severity: .normal)
    }
    private func snap(_ provider: ProviderID, limits: [UsageLimit] = [],
                      fetchedAt: TimeInterval = 0, status: FetchStatus = .ok) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testBothOkLandInBoard() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(40)]))),
            StubUsageProvider(id: .openai, result: .success(snap(.openai, limits: [limit(50)])))
        ]
        let board = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
        XCTAssertEqual(board.snapshot(for: .openai)?.limits.first?.percentUsed, 50)
    }

    func testThrowingProviderBecomesErrorWithoutBlockingTheOther() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .failure(StubError())),
            StubUsageProvider(id: .openai, result: .success(snap(.openai, limits: [limit(50)])))
        ]
        let board = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertEqual(board.snapshot(for: .claude)?.status, .error(message: "Fetch failed"))
        XCTAssertEqual(board.snapshot(for: .claude)?.limits.isEmpty, true)
        XCTAssertEqual(board.snapshot(for: .openai)?.status, .ok)
    }

    func testStaleFetchKeepsPreviousGoodEntry() async {
        let previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100)])
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(
                snap(.claude, fetchedAt: 200, status: .stale(reason: "offline"))))
        ]
        let board = await UsageRefresher.refresh(previous, providers: providers)
        let claude = board.snapshot(for: .claude)
        XCTAssertEqual(claude?.limits, [limit(40)])
        XCTAssertEqual(claude?.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(claude?.status, .stale(reason: "offline"))
    }

    func testProvidersNotInListKeepTheirEntry() async {
        let previous = UsageBoard(snapshots: [snap(.openai, limits: [limit(5)], fetchedAt: 7)])
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(40)])))
        ]
        let board = await UsageRefresher.refresh(previous, providers: providers)
        XCTAssertEqual(board.snapshot(for: .openai)?.fetchedAt, Date(timeIntervalSince1970: 7))
        XCTAssertEqual(board.snapshots.count, 2)
    }

    func testProvidersRunConcurrently() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude)), delay: 0.4),
            StubUsageProvider(id: .openai, result: .success(snap(.openai)), delay: 0.4)
        ]
        let start = Date()
        _ = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.7)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter UsageRefresherTests`
Expected: compile error, `UsageRefresher` not found.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/UsageCore/UsageRefresher.swift
import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard,
                               providers: [any UsageProvider]) async -> UsageBoard {
        let fetched = await withTaskGroup(of: UsageSnapshot.self,
                                          returning: [UsageSnapshot].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.fetch()
                    } catch {
                        return UsageSnapshot(provider: provider.id, fetchedAt: Date(),
                                             limits: [], status: .error(message: "Fetch failed"))
                    }
                }
            }
            var results: [UsageSnapshot] = []
            for await snapshot in group { results.append(snapshot) }
            return results
        }

        var updated = board
        for snapshot in fetched {
            updated.replace(snapshot.mergingLastGood(previous: board.snapshot(for: snapshot.provider)))
        }
        return updated
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter UsageRefresherTests`
Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/UsageRefresher.swift Tests/UsageCoreTests/UsageRefresherTests.swift Tests/UsageCoreTests/Support/Stubs.swift
git commit -m "feat(core): UsageRefresher runs providers concurrently with last-good merge

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Codex credentials reader

**Files:**
- Create: `Sources/UsageCore/Keychain/CodexAuthReader.swift`
- Create: `Sources/UsageCore/Keychain/CodexCredentials.swift`
- Create: `Tests/UsageCoreTests/Fixtures/codex_auth.json`
- Modify: `Tests/UsageCoreTests/Support/Stubs.swift` (add `StubCodexAuthReader`)
- Test: `Tests/UsageCoreTests/CodexCredentialsTests.swift`, `Tests/UsageCoreTests/FileCodexAuthReaderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct CodexAuth: Sendable, Equatable { accessToken: String; accountID: String?; expiresAt: Date? }
  public protocol CodexAuthReader: Sendable { func readCodexAuth() throws -> CodexAuth }
  public struct FileCodexAuthReader: CodexAuthReader { init(fileURL: URL = defaultURL); static var defaultURL: URL }
  struct CodexCredentials { static func parse(_ data: Data) throws -> CodexAuth }
  enum JWTClaims { static func expiry(of jwt: String) -> Date? }
  ```
  Errors: `TokenReaderError.notFound / .accessDenied / .malformed`.

- [ ] **Step 1: Add the fixture**

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "fake.id.token",
    "access_token": "fake.access.token",
    "refresh_token": "fake-refresh",
    "account_id": "00000000-0000-4000-8000-000000000000"
  },
  "last_refresh": "2026-09-17T02:52:51.808957Z"
}
```

- [ ] **Step 2: Add the stub reader** (append to `Support/Stubs.swift`)

```swift
struct StubCodexAuthReader: CodexAuthReader, @unchecked Sendable {
    let result: Result<CodexAuth, Error>
    func readCodexAuth() throws -> CodexAuth { try result.get() }
}
```

- [ ] **Step 3: Write the failing tests**

```swift
// Tests/UsageCoreTests/CodexCredentialsTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class CodexCredentialsTests: XCTestCase {
    private func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private func jwt(payload: String) -> String {
        "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig"
    }

    func testParseFixtureReturnsTokenAndAccountID() throws {
        let auth = try CodexCredentials.parse(Fixtures.data("codex_auth"))
        XCTAssertEqual(auth.accessToken, "fake.access.token")
        XCTAssertEqual(auth.accountID, "00000000-0000-4000-8000-000000000000")
        XCTAssertNil(auth.expiresAt)
    }

    func testTokensNullThrowsNotFound() {
        let json = #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexCredentials.parse(json)) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testEmptyAccessTokenThrowsNotFound() {
        let json = #"{"tokens":{"access_token":"","account_id":"a"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexCredentials.parse(json)) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testBadJSONThrowsMalformed() {
        XCTAssertThrowsError(try CodexCredentials.parse("nope".data(using: .utf8)!)) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }

    func testMissingAccountIDIsNil() throws {
        let json = #"{"tokens":{"access_token":"t"}}"#.data(using: .utf8)!
        XCTAssertNil(try CodexCredentials.parse(json).accountID)
    }

    func testExpiryFromJWTExpClaim() throws {
        let token = jwt(payload: #"{"exp":1790477571,"sub":"x"}"#)
        let json = #"{"tokens":{"access_token":"\#(token)"}}"#.data(using: .utf8)!
        XCTAssertEqual(try CodexCredentials.parse(json).expiresAt,
                       Date(timeIntervalSince1970: 1_790_477_571))
    }

    func testJWTWithoutExpGivesNilExpiry() {
        XCTAssertNil(JWTClaims.expiry(of: jwt(payload: #"{"sub":"x"}"#)))
    }

    func testNonJWTGivesNilExpiry() {
        XCTAssertNil(JWTClaims.expiry(of: "not-a-jwt"))
        XCTAssertNil(JWTClaims.expiry(of: "a.b"))
    }

    func testJWTPayloadNeedingPaddingDecodes() {
        // payload length chosen so base64url output is not a multiple of 4
        let token = jwt(payload: #"{"exp":1}"#)
        XCTAssertEqual(JWTClaims.expiry(of: token), Date(timeIntervalSince1970: 1))
    }
}
```

```swift
// Tests/UsageCoreTests/FileCodexAuthReaderTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class FileCodexAuthReaderTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testMissingFileThrowsNotFound() throws {
        let reader = FileCodexAuthReader(fileURL: try tempDir().appendingPathComponent("auth.json"))
        XCTAssertThrowsError(try reader.readCodexAuth()) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testReadsValidFile() throws {
        let url = try tempDir().appendingPathComponent("auth.json")
        try Fixtures.data("codex_auth").write(to: url)
        let auth = try FileCodexAuthReader(fileURL: url).readCodexAuth()
        XCTAssertEqual(auth.accessToken, "fake.access.token")
    }

    func testBadFileThrowsMalformed() throws {
        let url = try tempDir().appendingPathComponent("auth.json")
        try "{".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try FileCodexAuthReader(fileURL: url).readCodexAuth()) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }

    func testDefaultURLEndsWithCodexAuthJSON() {
        XCTAssertEqual(FileCodexAuthReader.defaultURL.lastPathComponent, "auth.json")
        XCTAssertEqual(FileCodexAuthReader.defaultURL.deletingLastPathComponent().lastPathComponent, ".codex")
    }
}
```

Note: `testDefaultURLEndsWithCodexAuthJSON` assumes `CODEX_HOME` is unset in the test environment. If it is set, `.codex` may differ; that is acceptable locally but do not set `CODEX_HOME` in CI.

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter 'CodexCredentialsTests|FileCodexAuthReaderTests'`
Expected: compile error, `CodexCredentials`, `JWTClaims`, `FileCodexAuthReader` not found.

- [ ] **Step 5: Write minimal implementation**

```swift
// Sources/UsageCore/Keychain/CodexAuthReader.swift
import Foundation

public struct CodexAuth: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let expiresAt: Date?

    public init(accessToken: String, accountID: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }
}

public protocol CodexAuthReader: Sendable {
    func readCodexAuth() throws -> CodexAuth
}

public struct FileCodexAuthReader: CodexAuthReader {
    private let fileURL: URL

    public init(fileURL: URL = FileCodexAuthReader.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent("auth.json")
    }

    public func readCodexAuth() throws -> CodexAuth {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw TokenReaderError.notFound }
        guard let data = fm.contents(atPath: fileURL.path) else { throw TokenReaderError.accessDenied }
        return try CodexCredentials.parse(data)
    }
}
```

```swift
// Sources/UsageCore/Keychain/CodexCredentials.swift
import Foundation

struct CodexCredentials: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let accessToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }

    let tokens: Tokens?

    static func parse(_ data: Data) throws -> CodexAuth {
        let credentials: CodexCredentials
        do {
            credentials = try JSONDecoder().decode(CodexCredentials.self, from: data)
        } catch {
            throw TokenReaderError.malformed
        }
        guard let token = credentials.tokens?.accessToken, !token.isEmpty else {
            throw TokenReaderError.notFound
        }
        return CodexAuth(accessToken: token,
                         accountID: credentials.tokens?.accountId,
                         expiresAt: JWTClaims.expiry(of: token))
    }
}

enum JWTClaims {
    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter 'CodexCredentialsTests|FileCodexAuthReaderTests'`
Expected: 13 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageCore/Keychain/CodexAuthReader.swift Sources/UsageCore/Keychain/CodexCredentials.swift Tests/UsageCoreTests/Fixtures/codex_auth.json Tests/UsageCoreTests/CodexCredentialsTests.swift Tests/UsageCoreTests/FileCodexAuthReaderTests.swift Tests/UsageCoreTests/Support/Stubs.swift
git commit -m "feat(core): read-only Codex auth.json reader with JWT expiry

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: OpenAI usage DTO + fixture

**Files:**
- Create: `Sources/UsageCore/Providers/OpenAI/OpenAIUsageDTO.swift`
- Create: `Tests/UsageCoreTests/Fixtures/openai_usage_response.json`
- Test: `Tests/UsageCoreTests/OpenAIUsageDTOTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct OpenAIUsageResponse: Decodable, Sendable {
      let rateLimit: RateLimit?
      struct RateLimit: Decodable, Sendable { let primaryWindow: Window?; let secondaryWindow: Window? }
      struct Window: Decodable, Sendable { let usedPercent: Double; let limitWindowSeconds: Int?; let resetAt: Double? }
  }
  ```

- [ ] **Step 1: Add the fixture** (synthetic numbers, placeholder ids)

```json
{
  "user_id": "user-placeholder",
  "account_id": "00000000-0000-4000-8000-000000000000",
  "email": "user@example.com",
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 32,
      "limit_window_seconds": 18000,
      "reset_after_seconds": 12341,
      "reset_at": 1789726348
    },
    "secondary_window": {
      "used_percent": 56,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 169749,
      "reset_at": 1789883756
    }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": null,
  "model_usage": {
    "gpt-6-astra": { "available": true, "available_at": null, "credits_would_enable": false }
  },
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0",
    "approx_local_messages": [0, 0],
    "approx_cloud_messages": [0, 0]
  },
  "spend_control": { "reached": false, "individual_limit": null },
  "rate_limit_reached_type": null,
  "promo": null,
  "rate_limit_reset_credits": { "available_count": 0, "applicable_available_count": 0 }
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/UsageCoreTests/OpenAIUsageDTOTests.swift
import XCTest
@testable import UsageCore

final class OpenAIUsageDTOTests: XCTestCase {
    func testDecodesFixture() throws {
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self,
                                         from: Fixtures.data("openai_usage_response"))
        XCTAssertEqual(r.rateLimit?.primaryWindow?.usedPercent, 32)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.limitWindowSeconds, 18000)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.resetAt, 1_789_726_348)
        XCTAssertEqual(r.rateLimit?.secondaryWindow?.usedPercent, 56)
        XCTAssertEqual(r.rateLimit?.secondaryWindow?.limitWindowSeconds, 604_800)
    }

    func testIntegerPercentDecodesAsDouble() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":7}}}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: json)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.usedPercent, 7.0)
        XCTAssertNil(r.rateLimit?.primaryWindow?.limitWindowSeconds)
        XCTAssertNil(r.rateLimit?.secondaryWindow)
    }

    func testNullRateLimitDecodes() throws {
        let json = #"{"plan_type":"free","rate_limit":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: json)
        XCTAssertNil(r.rateLimit)
    }

    func testMissingRateLimitDecodes() throws {
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: "{}".data(using: .utf8)!)
        XCTAssertNil(r.rateLimit)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter OpenAIUsageDTOTests`
Expected: compile error, `OpenAIUsageResponse` not found.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/UsageCore/Providers/OpenAI/OpenAIUsageDTO.swift
import Foundation

struct OpenAIUsageResponse: Decodable, Sendable {
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable, Sendable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(primaryWindow: Window?, secondaryWindow: Window?) {
            self.primaryWindow = primaryWindow
            self.secondaryWindow = secondaryWindow
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }

        init(usedPercent: Double, limitWindowSeconds: Int?, resetAt: Double?) {
            self.usedPercent = usedPercent
            self.limitWindowSeconds = limitWindowSeconds
            self.resetAt = resetAt
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter OpenAIUsageDTOTests`
Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/Providers/OpenAI/OpenAIUsageDTO.swift Tests/UsageCoreTests/Fixtures/openai_usage_response.json Tests/UsageCoreTests/OpenAIUsageDTOTests.swift
git commit -m "feat(core): OpenAI usage response DTO + fixture

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: `OpenAIUsageMapper`

**Files:**
- Create: `Sources/UsageCore/Providers/OpenAI/OpenAIUsageMapper.swift`
- Test: `Tests/UsageCoreTests/OpenAIUsageMapperTests.swift`

**Interfaces:**
- Consumes: `OpenAIUsageResponse.RateLimit`, `.Window` (Task 9), `Severity.from`.
- Produces: `enum OpenAIUsageMapper { static func map(_ rateLimit: OpenAIUsageResponse.RateLimit?, warning: Double, critical: Double) -> [UsageLimit]; static func label(windowSeconds: Int?, fallback: String) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/UsageCoreTests/OpenAIUsageMapperTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageMapperTests: XCTestCase {
    private func window(_ pct: Double, seconds: Int? = 18000, resetAt: Double? = 1_789_726_348)
        -> OpenAIUsageResponse.Window {
        OpenAIUsageResponse.Window(usedPercent: pct, limitWindowSeconds: seconds, resetAt: resetAt)
    }
    private func rateLimit(primary: OpenAIUsageResponse.Window?, secondary: OpenAIUsageResponse.Window?)
        -> OpenAIUsageResponse.RateLimit {
        OpenAIUsageResponse.RateLimit(primaryWindow: primary, secondaryWindow: secondary)
    }

    func testPrimaryAndSecondaryMapToSessionAndWeekly() {
        let limits = OpenAIUsageMapper.map(
            rateLimit(primary: window(32), secondary: window(56, seconds: 604_800, resetAt: 1_789_883_756)),
            warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["session", "weekly_all"])
        XCTAssertEqual(limits.map(\.label), ["Session (5h)", "Weekly"])
        XCTAssertEqual(limits.map(\.percentUsed), [32, 56])
        XCTAssertEqual(limits[0].resetsAt, Date(timeIntervalSince1970: 1_789_726_348))
        XCTAssertEqual(limits[1].resetsAt, Date(timeIntervalSince1970: 1_789_883_756))
    }

    func testLabelRules() {
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 18000, fallback: "Session"), "Session (5h)")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 3600, fallback: "Session"), "Session (1h)")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 604_800, fallback: "Weekly"), "Weekly")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 259_200, fallback: "Weekly"), "3-day")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: nil, fallback: "Weekly"), "Weekly")
    }

    func testNilResetAtMapsToNil() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(1, resetAt: nil), secondary: nil),
                                           warning: 80, critical: 95)
        XCTAssertNil(limits[0].resetsAt)
    }

    func testMissingWindowIsOmitted() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: nil, secondary: window(56, seconds: 604_800)),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
    }

    func testNilRateLimitMapsToEmpty() {
        XCTAssertEqual(OpenAIUsageMapper.map(nil, warning: 80, critical: 95), [])
    }

    func testSeverityFromThresholds() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(82), secondary: window(96)),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.severity), [.warning, .critical])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OpenAIUsageMapperTests`
Expected: compile error, `OpenAIUsageMapper` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Providers/OpenAI/OpenAIUsageMapper.swift
import Foundation

enum OpenAIUsageMapper {
    static func map(_ rateLimit: OpenAIUsageResponse.RateLimit?,
                    warning: Double, critical: Double) -> [UsageLimit] {
        guard let rateLimit else { return [] }
        var limits: [UsageLimit] = []
        if let window = rateLimit.primaryWindow {
            limits.append(limit(window, id: "session", fallback: "Session",
                                warning: warning, critical: critical))
        }
        if let window = rateLimit.secondaryWindow {
            limits.append(limit(window, id: "weekly_all", fallback: "Weekly",
                                warning: warning, critical: critical))
        }
        return limits
    }

    static func label(windowSeconds: Int?, fallback: String) -> String {
        guard let seconds = windowSeconds else { return fallback }
        if seconds < 86_400 {
            return "Session (\(Int((Double(seconds) / 3600).rounded()))h)"
        }
        if seconds == 604_800 { return "Weekly" }
        return "\(Int((Double(seconds) / 86_400).rounded()))-day"
    }

    private static func limit(_ window: OpenAIUsageResponse.Window, id: String, fallback: String,
                              warning: Double, critical: Double) -> UsageLimit {
        UsageLimit(id: id,
                   label: label(windowSeconds: window.limitWindowSeconds, fallback: fallback),
                   percentUsed: window.usedPercent,
                   resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) },
                   severity: Severity.from(percent: window.usedPercent,
                                           warning: warning, critical: critical))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OpenAIUsageMapperTests`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Providers/OpenAI/OpenAIUsageMapper.swift Tests/UsageCoreTests/OpenAIUsageMapperTests.swift
git commit -m "feat(core): map OpenAI rate-limit windows to UsageLimit

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: `OpenAIUsageProvider` (provider-specific behavior)

**Files:**
- Create: `Sources/UsageCore/Providers/OpenAI/OpenAIUsageProvider.swift`
- Test: `Tests/UsageCoreTests/OpenAIUsageProviderTests.swift`

**Interfaces:**
- Consumes: `CodexAuthReader`, `CodexAuth` (Task 8), `OpenAIUsageResponse` (Task 9), `OpenAIUsageMapper` (Task 10), `UsageHTTPClient`, `SpyHTTPClient`, `StubCodexAuthReader`.
- Produces: `public struct OpenAIUsageProvider: UsageProvider { init(authReader: CodexAuthReader, httpClient: UsageHTTPClient, baseURL: URL, warningThreshold: Double = 80, criticalThreshold: Double = 95) }`.

- [ ] **Step 1: Write the failing test** (only OpenAI-specific behavior; generic paths come in Task 12)

```swift
// Tests/UsageCoreTests/OpenAIUsageProviderTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageProviderTests: XCTestCase {
    private let base = URL(string: "https://chatgpt.com")!

    private func provider(auth: Result<CodexAuth, Error>, client: UsageHTTPClient) -> OpenAIUsageProvider {
        OpenAIUsageProvider(authReader: StubCodexAuthReader(result: auth), httpClient: client, baseURL: base)
    }
    private func validAuth(accountID: String? = "acct-1") -> CodexAuth {
        CodexAuth(accessToken: "tok", accountID: accountID, expiresAt: Date().addingTimeInterval(3600))
    }

    func testRequestsWhamUsagePathWithAccountHeader() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("openai_usage_response"), statusCode: 200)
        let snap = try await provider(auth: .success(validAuth()), client: spy).fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.map(\.id), ["session", "weekly_all"])
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(spy.calls[0].headers["Authorization"], "Bearer tok")
        XCTAssertEqual(spy.calls[0].headers["ChatGPT-Account-Id"], "acct-1")
        XCTAssertEqual(spy.calls[0].headers["Accept"], "application/json")
    }

    func testAccountHeaderOmittedWhenUnknown() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("openai_usage_response"), statusCode: 200)
        _ = try await provider(auth: .success(validAuth(accountID: nil)), client: spy).fetch()
        XCTAssertNil(spy.calls[0].headers["ChatGPT-Account-Id"])
    }

    func testAccessDeniedBecomesError() async throws {
        let snap = try await provider(auth: .failure(TokenReaderError.accessDenied),
                                      client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .error(message: "Can't read Codex credentials"))
    }

    func testMalformedBecomesError() async throws {
        let snap = try await provider(auth: .failure(TokenReaderError.malformed),
                                      client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .error(message: "Can't read Codex credentials"))
    }

    func testExpiredTokenMessageNamesCodex() async throws {
        let auth = CodexAuth(accessToken: "tok", accountID: nil, expiresAt: Date().addingTimeInterval(-1))
        let snap = try await provider(auth: .success(auth), client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Token expired — open Codex to refresh"))
    }

    func test401MessageNamesCodex() async throws {
        let snap = try await provider(auth: .success(validAuth()), client: SpyHTTPClient(statusCode: 401)).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Unauthorized — open Codex to refresh"))
    }

    func testNullRateLimitGivesOkWithNoLimits() async throws {
        let body = #"{"rate_limit":null}"#.data(using: .utf8)!
        let snap = try await provider(auth: .success(validAuth()), client: SpyHTTPClient(data: body)).fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertTrue(snap.limits.isEmpty)
    }

    func testProviderIDIsOpenAI() {
        XCTAssertEqual(provider(auth: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).id, .openai)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OpenAIUsageProviderTests`
Expected: compile error, `OpenAIUsageProvider` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/Providers/OpenAI/OpenAIUsageProvider.swift
import Foundation

public struct OpenAIUsageProvider: UsageProvider {
    public let id: ProviderID = .openai

    private let authReader: CodexAuthReader
    private let httpClient: UsageHTTPClient
    private let baseURL: URL
    private let warningThreshold: Double
    private let criticalThreshold: Double

    public init(authReader: CodexAuthReader, httpClient: UsageHTTPClient, baseURL: URL,
                warningThreshold: Double = 80, criticalThreshold: Double = 95) {
        self.authReader = authReader
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public func fetch() async throws -> UsageSnapshot {
        let now = Date()

        let auth: CodexAuth
        do {
            auth = try authReader.readCodexAuth()
        } catch TokenReaderError.notFound {
            return snapshot(now, .needsSignIn)
        } catch {
            return snapshot(now, .error(message: "Can't read Codex credentials"))
        }

        if let expiry = auth.expiresAt, expiry <= now {
            return snapshot(now, .stale(reason: "Token expired — open Codex to refresh"))
        }

        let url = baseURL.appendingPathComponent("backend-api/wham/usage")
        var headers = [
            "Authorization": "Bearer \(auth.accessToken)",
            "Accept": "application/json"
        ]
        if let accountID = auth.accountID {
            headers["ChatGPT-Account-Id"] = accountID
        }

        do {
            let (data, response) = try await httpClient.get(url, headers: headers)
            if response.statusCode == 401 {
                return snapshot(now, .stale(reason: "Unauthorized — open Codex to refresh"))
            }
            if response.statusCode == 429 {
                return snapshot(now, .stale(reason: "Rate limited — retrying"))
            }
            guard (200..<300).contains(response.statusCode) else {
                return snapshot(now, .error(message: "HTTP \(response.statusCode)"))
            }
            let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
            let limits = OpenAIUsageMapper.map(decoded.rateLimit,
                                               warning: warningThreshold,
                                               critical: criticalThreshold)
            return UsageSnapshot(provider: .openai, fetchedAt: now, limits: limits, status: .ok)
        } catch is URLError {
            return snapshot(now, .stale(reason: "Network unavailable — retrying"))
        } catch is DecodingError {
            return snapshot(now, .error(message: "Couldn't read usage data"))
        } catch {
            return snapshot(now, .error(message: "Unexpected error"))
        }
    }

    private func snapshot(_ now: Date, _ status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: .openai, fetchedAt: now, limits: [], status: status)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OpenAIUsageProviderTests`
Expected: 8 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Providers/OpenAI/OpenAIUsageProvider.swift Tests/UsageCoreTests/OpenAIUsageProviderTests.swift
git commit -m "feat(core): OpenAIUsageProvider (ChatGPT wham/usage)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: `UsageProvider` contract, run against both providers

**Files:**
- Create: `Tests/UsageCoreTests/Contract/UsageProviderContract.swift`
- Create: `Tests/UsageCoreTests/ClaudeUsageProviderContractTests.swift`
- Create: `Tests/UsageCoreTests/OpenAIUsageProviderContractTests.swift`
- Modify: `Tests/UsageCoreTests/ClaudeUsageProviderTests.swift` (remove generic duplicates, add Claude-only header/path tests)

**Interfaces:**
- Consumes: `ClaudeUsageProvider`, `OpenAIUsageProvider`, `StubTokenReader`, `StubCodexAuthReader`, `SpyHTTPClient`, `ThrowingHTTPClient`, `Fixtures`.
- Produces: `CredentialOutcome`, `ProviderContractSubject`, `UsageProviderContract.c1…c9`.

- [ ] **Step 1: Write the contract helper**

```swift
// Tests/UsageCoreTests/Contract/UsageProviderContract.swift
import XCTest
import Foundation
@testable import UsageCore

enum CredentialOutcome: CaseIterable {
    case valid, expired, notFound, accessDenied, malformed
}

struct ProviderContractSubject {
    let expectedID: ProviderID
    let validFixture: String
    let expectedLimitCount: Int
    let make: (_ credential: CredentialOutcome, _ client: UsageHTTPClient) -> any UsageProvider
}

/// Guarantees every UsageProvider must honor; each check is called from a per-provider test class.
enum UsageProviderContract {
    static let token = "contract-token"
    static let warning = 80.0
    static let critical = 95.0

    private static func fixture(_ s: ProviderContractSubject) throws -> Data {
        try Fixtures.data(s.validFixture)
    }

    /// C1: fetch() never throws — every failure becomes a FetchStatus.
    static func c1NeverThrows(_ s: ProviderContractSubject,
                              file: StaticString = #filePath, line: UInt = #line) async {
        let clients: [UsageHTTPClient] = [
            SpyHTTPClient(data: (try? fixture(s)) ?? Data(), statusCode: 200),
            SpyHTTPClient(statusCode: 401), SpyHTTPClient(statusCode: 429),
            SpyHTTPClient(statusCode: 500), SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200),
            ThrowingHTTPClient(error: URLError(.notConnectedToInternet)),
            ThrowingHTTPClient(error: StubError())
        ]
        for outcome in CredentialOutcome.allCases {
            for client in clients {
                do { _ = try await s.make(outcome, client).fetch() }
                catch { XCTFail("threw for \(outcome) / \(type(of: client)): \(error)", file: file, line: line) }
            }
        }
    }

    /// C2: snapshot.provider == provider.id.
    static func c2ProviderIDMatches(_ s: ProviderContractSubject,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let p = s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200))
        XCTAssertEqual(p.id, s.expectedID, file: file, line: line)
        let snap = try await p.fetch()
        XCTAssertEqual(snap.provider, s.expectedID, file: file, line: line)
    }

    /// C3: any non-.ok status ⇒ no limits.
    static func c3NonOkHasNoLimits(_ s: ProviderContractSubject,
                                   file: StaticString = #filePath, line: UInt = #line) async throws {
        let cases: [(CredentialOutcome, UsageHTTPClient)] = [
            (.notFound, SpyHTTPClient()), (.expired, SpyHTTPClient()),
            (.accessDenied, SpyHTTPClient()), (.malformed, SpyHTTPClient()),
            (.valid, SpyHTTPClient(statusCode: 401)), (.valid, SpyHTTPClient(statusCode: 500)),
            (.valid, ThrowingHTTPClient(error: URLError(.timedOut))),
            (.valid, SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200))
        ]
        for (outcome, client) in cases {
            let snap = try await s.make(outcome, client).fetch()
            XCTAssertNotEqual(snap.status, .ok, "\(outcome)", file: file, line: line)
            XCTAssertTrue(snap.limits.isEmpty, "\(outcome) \(type(of: client))", file: file, line: line)
        }
    }

    /// C4: valid fixture ⇒ expected limit count and severities derived from thresholds.
    static func c4OkMapsFixture(_ s: ProviderContractSubject,
                                file: StaticString = #filePath, line: UInt = #line) async throws {
        let snap = try await s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200)).fetch()
        XCTAssertEqual(snap.status, .ok, file: file, line: line)
        XCTAssertEqual(snap.limits.count, s.expectedLimitCount, file: file, line: line)
        for limit in snap.limits {
            XCTAssertEqual(limit.severity,
                           Severity.from(percent: limit.percentUsed, warning: warning, critical: critical),
                           limit.id, file: file, line: line)
            XCTAssertFalse(limit.id.isEmpty, file: file, line: line)
            XCTAssertFalse(limit.label.isEmpty, file: file, line: line)
        }
    }

    /// C5: credential not found ⇒ .needsSignIn.
    static func c5NotFoundNeedsSignIn(_ s: ProviderContractSubject,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        let snap = try await s.make(.notFound, SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .needsSignIn, file: file, line: line)
    }

    /// C6: expired credential ⇒ .stale and zero HTTP calls.
    static func c6ExpiredIsStaleWithoutNetwork(_ s: ProviderContractSubject,
                                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let spy = SpyHTTPClient()
        let snap = try await s.make(.expired, spy).fetch()
        guard case .stale = snap.status else {
            return XCTFail("expected .stale, got \(snap.status)", file: file, line: line)
        }
        XCTAssertTrue(spy.calls.isEmpty, file: file, line: line)
    }

    /// C7: HTTP outcome → status class.
    static func c7HTTPStatusMapping(_ s: ProviderContractSubject,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        func isStale(_ st: FetchStatus) -> Bool { if case .stale = st { return true }; return false }
        func isError(_ st: FetchStatus) -> Bool { if case .error = st { return true }; return false }

        let status401 = try await s.make(.valid, SpyHTTPClient(statusCode: 401)).fetch().status
        XCTAssertTrue(isStale(status401), "401", file: file, line: line)
        let status429 = try await s.make(.valid, SpyHTTPClient(statusCode: 429)).fetch().status
        XCTAssertTrue(isStale(status429), "429", file: file, line: line)
        let status500 = try await s.make(.valid, SpyHTTPClient(statusCode: 500)).fetch().status
        XCTAssertTrue(isError(status500), "500", file: file, line: line)
        let statusURLError = try await s.make(.valid, ThrowingHTTPClient(error: URLError(.notConnectedToInternet))).fetch().status
        XCTAssertTrue(isStale(statusURLError), "URLError", file: file, line: line)
        let statusBadJSON = try await s.make(.valid, SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200)).fetch().status
        XCTAssertTrue(isError(statusBadJSON), "bad JSON", file: file, line: line)
    }

    /// C8: exactly one GET carrying the bearer token.
    static func c8SendsBearerOnce(_ s: ProviderContractSubject,
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        let spy = SpyHTTPClient(data: try fixture(s), statusCode: 200)
        _ = try await s.make(.valid, spy).fetch()
        XCTAssertEqual(spy.calls.count, 1, file: file, line: line)
        XCTAssertEqual(spy.calls.first?.headers["Authorization"], "Bearer \(token)", file: file, line: line)
    }

    /// C9: fetchedAt is "now".
    static func c9FetchedAtIsNow(_ s: ProviderContractSubject,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = Date()
        let snap = try await s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200)).fetch()
        let after = Date()
        XCTAssertGreaterThanOrEqual(snap.fetchedAt, before, file: file, line: line)
        XCTAssertLessThanOrEqual(snap.fetchedAt, after, file: file, line: line)
    }
}
```

- [ ] **Step 2: Write the per-provider contract test classes**

```swift
// Tests/UsageCoreTests/ClaudeUsageProviderContractTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class ClaudeUsageProviderContractTests: XCTestCase {
    private let subject = ProviderContractSubject(
        expectedID: .claude, validFixture: "usage_response", expectedLimitCount: 3
    ) { outcome, client in
        let token = UsageProviderContract.token
        let result: Result<ClaudeToken, Error>
        switch outcome {
        case .valid: result = .success(ClaudeToken(accessToken: token, expiresAt: Date().addingTimeInterval(3600)))
        case .expired: result = .success(ClaudeToken(accessToken: token, expiresAt: Date().addingTimeInterval(-10)))
        case .notFound: result = .failure(TokenReaderError.notFound)
        case .accessDenied: result = .failure(TokenReaderError.accessDenied)
        case .malformed: result = .failure(TokenReaderError.malformed)
        }
        return ClaudeUsageProvider(tokenReader: StubTokenReader(result: result), httpClient: client,
                                   baseURL: URL(string: "https://api.anthropic.com")!,
                                   warningThreshold: UsageProviderContract.warning,
                                   criticalThreshold: UsageProviderContract.critical)
    }

    func testC1NeverThrows() async { await UsageProviderContract.c1NeverThrows(subject) }
    func testC2ProviderIDMatches() async throws { try await UsageProviderContract.c2ProviderIDMatches(subject) }
    func testC3NonOkHasNoLimits() async throws { try await UsageProviderContract.c3NonOkHasNoLimits(subject) }
    func testC4OkMapsFixture() async throws { try await UsageProviderContract.c4OkMapsFixture(subject) }
    func testC5NotFoundNeedsSignIn() async throws { try await UsageProviderContract.c5NotFoundNeedsSignIn(subject) }
    func testC6ExpiredIsStaleWithoutNetwork() async throws { try await UsageProviderContract.c6ExpiredIsStaleWithoutNetwork(subject) }
    func testC7HTTPStatusMapping() async throws { try await UsageProviderContract.c7HTTPStatusMapping(subject) }
    func testC8SendsBearerOnce() async throws { try await UsageProviderContract.c8SendsBearerOnce(subject) }
    func testC9FetchedAtIsNow() async throws { try await UsageProviderContract.c9FetchedAtIsNow(subject) }
}
```

```swift
// Tests/UsageCoreTests/OpenAIUsageProviderContractTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageProviderContractTests: XCTestCase {
    private let subject = ProviderContractSubject(
        expectedID: .openai, validFixture: "openai_usage_response", expectedLimitCount: 2
    ) { outcome, client in
        let token = UsageProviderContract.token
        let result: Result<CodexAuth, Error>
        switch outcome {
        case .valid: result = .success(CodexAuth(accessToken: token, accountID: "acct", expiresAt: Date().addingTimeInterval(3600)))
        case .expired: result = .success(CodexAuth(accessToken: token, accountID: "acct", expiresAt: Date().addingTimeInterval(-10)))
        case .notFound: result = .failure(TokenReaderError.notFound)
        case .accessDenied: result = .failure(TokenReaderError.accessDenied)
        case .malformed: result = .failure(TokenReaderError.malformed)
        }
        return OpenAIUsageProvider(authReader: StubCodexAuthReader(result: result), httpClient: client,
                                   baseURL: URL(string: "https://chatgpt.com")!,
                                   warningThreshold: UsageProviderContract.warning,
                                   criticalThreshold: UsageProviderContract.critical)
    }

    func testC1NeverThrows() async { await UsageProviderContract.c1NeverThrows(subject) }
    func testC2ProviderIDMatches() async throws { try await UsageProviderContract.c2ProviderIDMatches(subject) }
    func testC3NonOkHasNoLimits() async throws { try await UsageProviderContract.c3NonOkHasNoLimits(subject) }
    func testC4OkMapsFixture() async throws { try await UsageProviderContract.c4OkMapsFixture(subject) }
    func testC5NotFoundNeedsSignIn() async throws { try await UsageProviderContract.c5NotFoundNeedsSignIn(subject) }
    func testC6ExpiredIsStaleWithoutNetwork() async throws { try await UsageProviderContract.c6ExpiredIsStaleWithoutNetwork(subject) }
    func testC7HTTPStatusMapping() async throws { try await UsageProviderContract.c7HTTPStatusMapping(subject) }
    func testC8SendsBearerOnce() async throws { try await UsageProviderContract.c8SendsBearerOnce(subject) }
    func testC9FetchedAtIsNow() async throws { try await UsageProviderContract.c9FetchedAtIsNow(subject) }
}
```

- [ ] **Step 3: Run the contract tests**

Run: `swift test --filter 'ProviderContractTests'`
Expected: 18 tests, 0 failures (both providers already satisfy the contract; this step proves it). If any fails, fix the provider, not the contract.

- [ ] **Step 4: Trim `ClaudeUsageProviderTests` to Claude-only behavior**

Replace the file body with:

```swift
// Tests/UsageCoreTests/ClaudeUsageProviderTests.swift
import XCTest
import Foundation
@testable import UsageCore

/// Claude-only behavior. Generic provider guarantees live in ClaudeUsageProviderContractTests.
final class ClaudeUsageProviderTests: XCTestCase {
    private let base = URL(string: "https://api.anthropic.com")!

    private func provider(token: Result<ClaudeToken, Error>,
                          client: UsageHTTPClient) -> ClaudeUsageProvider {
        ClaudeUsageProvider(tokenReader: StubTokenReader(result: token),
                            httpClient: client, baseURL: base)
    }

    func testRequestsOAuthUsagePathWithBetaHeader() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("usage_response"), statusCode: 200)
        let token = ClaudeToken(accessToken: "t", expiresAt: Date().addingTimeInterval(3600))
        let snap = try await provider(token: .success(token), client: spy).fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.count, 3)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].url.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(spy.calls[0].headers["anthropic-beta"], "oauth-2025-04-20")
    }

    func testAccessDeniedReturnsKeychainDenied() async throws {
        let snap = try await provider(token: .failure(TokenReaderError.accessDenied),
                                      client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .keychainDenied)
    }

    func testExpiredTokenMessageNamesClaudeCode() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: Date().addingTimeInterval(-10))
        let snap = try await provider(token: .success(token), client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Token expired — open Claude Code to refresh"))
    }

    func test401MessageNamesClaudeCode() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: nil)
        let snap = try await provider(token: .success(token), client: SpyHTTPClient(statusCode: 401)).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Unauthorized — open Claude Code to refresh"))
    }
}
```

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 0 failures, 2 skipped.

- [ ] **Step 6: Commit**

```bash
git add Tests/UsageCoreTests/Contract Tests/UsageCoreTests/ClaudeUsageProviderContractTests.swift Tests/UsageCoreTests/OpenAIUsageProviderContractTests.swift Tests/UsageCoreTests/ClaudeUsageProviderTests.swift
git commit -m "test(core): UsageProvider contract run against Claude and OpenAI

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Registry wires both providers + opt-in live test

**Files:**
- Modify: `Sources/UsageCore/ProviderRegistry.swift`
- Modify: `Tests/UsageCoreTests/ProviderRegistryTests.swift`
- Create: `Tests/UsageCoreTests/CodexAuthIntegrationTests.swift`

**Interfaces:**
- Produces: `ProviderRegistry.makeDefault(tokenReader: TokenReader, codexAuthReader: CodexAuthReader, httpClient: UsageHTTPClient, claudeBaseURL: URL, openAIBaseURL: URL) -> ProviderRegistry`.

- [ ] **Step 1: Write the failing tests** (replace `ProviderRegistryTests`)

```swift
// Tests/UsageCoreTests/ProviderRegistryTests.swift
import XCTest
import Foundation
@testable import UsageCore

final class ProviderRegistryTests: XCTestCase {
    private func registry() -> ProviderRegistry {
        ProviderRegistry.makeDefault(
            tokenReader: StubTokenReader(result: .failure(TokenReaderError.notFound)),
            codexAuthReader: StubCodexAuthReader(result: .failure(TokenReaderError.notFound)),
            httpClient: SpyHTTPClient(),
            claudeBaseURL: URL(string: "https://api.anthropic.com")!,
            openAIBaseURL: URL(string: "https://chatgpt.com")!)
    }

    func testDefaultRegistryMatchesDisplayOrder() {
        XCTAssertEqual(registry().providers.map(\.id), ProviderID.displayOrder)
    }

    func testNoDuplicateProviders() {
        let ids = registry().providers.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEachProviderIsWiredToItsOwnCredentialReader() async throws {
        for provider in registry().providers {
            let snap = try await provider.fetch()
            XCTAssertEqual(snap.provider, provider.id)
            XCTAssertEqual(snap.status, .needsSignIn, "\(provider.id)")
        }
    }
}
```

```swift
// Tests/UsageCoreTests/CodexAuthIntegrationTests.swift
import Foundation
import XCTest
@testable import UsageCore

final class CodexAuthIntegrationTests: XCTestCase {
    func testLiveFetchIsOkOrNeedsSignIn() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CODEX_INTEGRATION_TESTS"] != nil else {
            throw XCTSkip("Set RUN_CODEX_INTEGRATION_TESTS=1 to hit the real Codex auth file + network")
        }
        let provider = OpenAIUsageProvider(authReader: FileCodexAuthReader(),
                                           httpClient: URLSessionHTTPClient(),
                                           baseURL: URL(string: "https://chatgpt.com")!)
        let snap = try await provider.fetch()
        switch snap.status {
        case .ok, .needsSignIn, .stale: break
        case .error(let message): XCTFail("unexpected error: \(message)")
        case .keychainDenied: XCTFail("keychainDenied is not a Codex status")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'ProviderRegistryTests|CodexAuthIntegrationTests'`
Expected: compile error, `makeDefault` has no `codexAuthReader` parameter.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/UsageCore/ProviderRegistry.swift
import Foundation

public struct ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func makeDefault(tokenReader: TokenReader,
                                   codexAuthReader: CodexAuthReader,
                                   httpClient: UsageHTTPClient,
                                   claudeBaseURL: URL,
                                   openAIBaseURL: URL) -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeUsageProvider(tokenReader: tokenReader,
                                httpClient: httpClient,
                                baseURL: claudeBaseURL),
            OpenAIUsageProvider(authReader: codexAuthReader,
                                httpClient: httpClient,
                                baseURL: openAIBaseURL)
        ])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: 0 failures, 3 skipped (Keychain, App Group, Codex live).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/ProviderRegistry.swift Tests/UsageCoreTests/ProviderRegistryTests.swift Tests/UsageCoreTests/CodexAuthIntegrationTests.swift
git commit -m "feat(core): registry wires Claude and OpenAI providers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: App wiring — view model, label, notifications

**Files:**
- Modify: `App/UsageViewModel.swift`
- Modify: `App/MenuBarLabelView.swift`
- Modify: `App/NotificationManager.swift`

**Interfaces:**
- Consumes: `UsageBoard`, `UsageRefresher.refresh`, `UsageFormatter.compactLabel(for:)`, `ProviderRegistry.makeDefault(...)`, `FileCodexAuthReader()`, `ThresholdCrossing.provider`.
- Produces: `UsageViewModel.board: UsageBoard` (`@Published`), `NotificationManager.process(_ board: UsageBoard)`, `MenuBarLabelView(board:)`.

No unit tests in the app target; the app does not compile until Task 15 also lands (views still reference `snapshot`). Build verification is in Task 17.

- [ ] **Step 1: Rewrite `UsageViewModel`**

```swift
// App/UsageViewModel.swift
import Foundation
import Combine
import Network
import WidgetKit
import UsageCore

@MainActor
final class UsageViewModel: ObservableObject {
    static let appGroupID = "group.com.gilad.agentusage"

    @Published var board: UsageBoard
    var refreshInterval: TimeInterval

    private let registry: ProviderRegistry
    private let store: SnapshotStore
    private let notifications: NotificationManager
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var wasConnected = true

    init(refreshInterval: TimeInterval? = nil) {
        let stored = UserDefaults.standard.object(forKey: "refreshInterval") as? Double
        self.refreshInterval = refreshInterval ?? stored ?? 780   // default 13 min
        let env = ProcessInfo.processInfo.environment
        let claudeBase = env["ANTHROPIC_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://api.anthropic.com")!
        let openAIBase = env["CHATGPT_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://chatgpt.com")!
        self.registry = ProviderRegistry.makeDefault(
            tokenReader: KeychainTokenReader(),
            codexAuthReader: FileCodexAuthReader(),
            httpClient: URLSessionHTTPClient(),
            claudeBaseURL: claudeBase,
            openAIBaseURL: openAIBase)
        self.store = SnapshotStore(appGroupID: Self.appGroupID)
        self.notifications = NotificationManager()
        self.board = store.load() ?? UsageBoard()
        notifications.requestAuthorization()
        start()
        startNetworkMonitoring()
    }

    /// Refresh immediately when the network comes back (like Gmail reconnecting),
    /// instead of waiting for the next scheduled tick.
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if connected && !self.wasConnected {
                    await self.refresh()
                }
                self.wasConnected = connected
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.gilad.agentusage.network"))
    }

    func start() {
        timer?.invalidate()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        let updated = await UsageRefresher.refresh(board, providers: registry.providers)
        board = updated
        try? store.save(updated)
        notifications.process(updated)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 2: Rewrite `MenuBarLabelView`** (the app-side `UsageFormatter` is deleted; core owns it)

```swift
// App/MenuBarLabelView.swift
import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    let board: UsageBoard

    var body: some View {
        Text(UsageFormatter.compactLabel(for: board))
    }
}
```

- [ ] **Step 3: Update `NotificationManager.process`** — replace the `process` and `post` functions:

```swift
    func process(_ board: UsageBoard) {
        guard let center else { return }
        let thresholds = [
            defaults.object(forKey: "warningThreshold") as? Double ?? 80,
            defaults.object(forKey: "criticalThreshold") as? Double ?? 95
        ]
        var state = loadState()
        var crossings: [ThresholdCrossing] = []
        for snapshot in board.snapshots where snapshot.status == .ok {
            crossings += ThresholdEvaluator.evaluate(snapshot, state: &state, thresholds: thresholds)
        }
        saveState(state)
        for crossing in crossings {
            post(crossing, to: center)
        }
    }

    private func post(_ crossing: ThresholdCrossing, to center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "\(crossing.provider.displayName) \(crossing.limit.label) at \(Int(crossing.limit.percentUsed.rounded()))%"
        content.body = "You've crossed the \(Int(crossing.threshold))% threshold for this limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)
        center.add(request)
    }
```

- [ ] **Step 4: Update the label call site in `App/AgentUsageApp.swift`**

Change `MenuBarLabelView(snapshot: viewModel.snapshot)` to `MenuBarLabelView(board: viewModel.board)`.

- [ ] **Step 5: Commit** (build is verified after Task 15)

```bash
git add App/UsageViewModel.swift App/MenuBarLabelView.swift App/NotificationManager.swift App/AgentUsageApp.swift
git commit -m "feat(app): view model publishes a UsageBoard via UsageRefresher; provider-aware notifications

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: App UI — stacked provider sections

**Files:**
- Create: `App/ProviderSection.swift`
- Modify: `App/MenuContentView.swift`
- Modify: `App/DesktopPanelView.swift`

**Interfaces:**
- Consumes: `UsageViewModel.board`, `UsageSnapshot`, `ProviderID.displayName/clientName`, `LimitRow` (existing, stays in `MenuContentView.swift`).
- Produces: `ProviderSection(snapshot:)`.

- [ ] **Step 1: Create `ProviderSection`**

```swift
// App/ProviderSection.swift
import SwiftUI
import UsageCore

struct ProviderSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            statusRow
            if snapshot.limits.isEmpty {
                if snapshot.status == .ok {
                    Text("No usage data.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(snapshot.limits) { LimitRow(limit: $0) }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch snapshot.status {
        case .ok:
            EmptyView()
        case .stale(let reason):
            Label(reason, systemImage: "clock.badge.exclamationmark")
                .font(.caption).foregroundStyle(.orange)
        case .needsSignIn:
            Label("Sign in to \(snapshot.provider.clientName) first.",
                  systemImage: "person.crop.circle.badge.questionmark")
                .font(.caption).foregroundStyle(.orange)
        case .keychainDenied:
            Label("Keychain access denied — grant access.", systemImage: "lock.slash")
                .font(.caption).foregroundStyle(.red)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: Rewrite the top of `MenuContentView.body`** — replace everything from `VStack(alignment: .leading, spacing: 8) {` down to the first `Divider()` with:

```swift
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.board.isEmpty {
                Text("Loading…")
            } else {
                ForEach(Array(viewModel.board.snapshots.enumerated()), id: \.element.provider) { index, snapshot in
                    if index > 0 { Divider() }
                    ProviderSection(snapshot: snapshot)
                }
                if let updated = viewModel.board.latestFetchedAt {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
```

Then delete the private `statusRow(_:)` function from `MenuContentView` (it now lives in `ProviderSection`). Keep `LimitRow` and `confirmQuit` in this file. Change the alert text to:

```swift
        alert.messageText = "Quit Agent Usage?"
```

- [ ] **Step 3: Rewrite `DesktopPanelView`**

```swift
// App/DesktopPanelView.swift
import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Agent Usage").font(.caption.bold())
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            content
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.22, blue: 0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.board.isEmpty {
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.board.snapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 { Divider() }
                ProviderSection(snapshot: snapshot)
            }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add App/ProviderSection.swift App/MenuContentView.swift App/DesktopPanelView.swift
git commit -m "feat(app): stacked Claude/OpenAI sections in menu and floating panel

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: Widget renders the board

**Files:**
- Modify: `Widget/AgentUsageWidget.swift`
- Modify: `Widget/UsageWidgetView.swift`

**Interfaces:**
- Consumes: `SnapshotStore.load() -> UsageBoard?`, `UsageBoard.snapshots/tightestLimits/latestFetchedAt`, `ProviderID.displayName/glyph`.

- [ ] **Step 1: Update the entry and provider**

In `Widget/AgentUsageWidget.swift`:

```swift
struct UsageEntry: TimelineEntry {
    let date: Date
    let board: UsageBoard?
}
```

Replace every `snapshot: store.load()` with `board: store.load()` and `snapshot: nil` with `board: nil`. Change the configuration text:

```swift
        .configurationDisplayName("Agent Usage")
        .description("Plan-quota usage for Claude and OpenAI.")
```

- [ ] **Step 2: Rewrite the widget view**

```swift
// Widget/UsageWidgetView.swift
import WidgetKit
import SwiftUI
import UsageCore

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let board = entry.board, !board.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Agent Usage").font(.caption.bold())
                    Spacer()
                    if let fetched = board.latestFetchedAt, isStale(fetched) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                if family == .systemSmall {
                    smallRows(board)
                } else {
                    mediumRows(board)
                }
            }
            .padding(12)
        } else {
            Text("Open the app to sign in.")
                .font(.caption).padding(12)
        }
    }

    @ViewBuilder
    private func smallRows(_ board: UsageBoard) -> some View {
        if board.tightestLimits.isEmpty {
            Text("No data").font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(board.tightestLimits, id: \.provider) { item in
                bar(for: item.limit, title: "\(item.provider.glyph) \(item.provider.displayName)")
            }
        }
    }

    @ViewBuilder
    private func mediumRows(_ board: UsageBoard) -> some View {
        ForEach(board.snapshots, id: \.provider) { snapshot in
            Text(snapshot.provider.displayName).font(.caption2.bold()).foregroundStyle(.secondary)
            let limits = displayLimits(snapshot)
            if limits.isEmpty {
                Text("No data").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(limits) { bar(for: $0, title: $0.label) }
            }
        }
    }

    private func displayLimits(_ snapshot: UsageSnapshot) -> [UsageLimit] {
        let session = snapshot.limits.first { $0.id == "session" }
        let weekly = snapshot.limits.first { $0.id == "weekly_all" }
        return [session, weekly].compactMap { $0 }
    }

    private func isStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 30 * 60
    }

    @ViewBuilder
    private func bar(for limit: UsageLimit, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2)
                Spacer()
                Text("\(Int(limit.percentUsed.rounded()))%").font(.caption2.monospacedDigit())
            }
            ProgressView(value: min(limit.percentUsed, 100), total: 100)
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Widget/AgentUsageWidget.swift Widget/UsageWidgetView.swift
git commit -m "feat(widget): render both providers from the UsageBoard

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: Build, run, verify, document

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Full unit suite**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed N tests, with 0 failures` and 3 skipped. N ≥ 100.

- [ ] **Step 2: Build app + widget**

```bash
xcodegen generate
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E 'warning:|error:|BUILD' 
```
Expected: `** BUILD SUCCEEDED **`, no `warning:` or `error:` lines. If the build fails, fix the compile error in the app/widget file it names; do not change `UsageCore` without a failing unit test first.

- [ ] **Step 3: Run and check visually**

```bash
pkill -x AgentUsageApp; open build/Build/Products/Debug/AgentUsageApp.app
```
Check: menu bar shows `◐NN%·⬡NN%`; dropdown shows a "Claude" section and an "OpenAI" section, each with limit rows; one "Updated …" line; floating panel (toggle in menu) shows both sections with the title "Agent Usage".

- [ ] **Step 4: Check the sign-in state for OpenAI**

```bash
mv ~/.codex/auth.json ~/.codex/auth.json.bak
```
Click refresh in the menu. Expected: OpenAI section shows "Sign in to Codex CLI first." and the label drops to `◐NN%`. Then restore and refresh:
```bash
mv ~/.codex/auth.json.bak ~/.codex/auth.json
```
Expected: OpenAI rows return.

- [ ] **Step 5: Update `STATUS.md`**

- Title/intro: the app shows Claude **and** OpenAI (ChatGPT/Codex) plan-quota usage.
- §1 table: add a row "OpenAI provider (Codex `auth.json` reader, `wham/usage`, DTO, mapper, contract tests)" → Done.
- §1 data source: add the ChatGPT endpoint paragraph from the spec (URL, headers, `~/.codex/auth.json`, JWT `exp`, read-only).
- §2: mention `UsageBoard`, `UsageRefresher`, `UsageFormatter` in core; `ProviderSection` in the app; store file is now `usage_board.json`.
- §3: update the `swift test` count line; add `RUN_CODEX_INTEGRATION_TESTS=1` to the opt-in list.
- §7: add the new spec and plan paths.

- [ ] **Step 6: Commit**

```bash
git add STATUS.md
git commit -m "docs: STATUS reflects OpenAI provider, UsageBoard, contract tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec coverage: `ProviderID` metadata (T1), `UsageBoard` (T2), last-good merge (T3), evaluator keys (T4), formatter (T5), store (T6), refresher (T7), Codex reader (T8), DTO (T9), mapper (T10), OpenAI provider (T11), contract (T12), registry + live test (T13), app wiring (T14), stacked UI + renames (T15), widget (T16), verification + STATUS (T17). Out-of-scope items are not planned.
- Type consistency: `UsageBoard.replace/snapshot(for:)/tightestLimits/latestFetchedAt/isEmpty`, `ProviderLimit(provider:limit:)`, `CodexAuth(accessToken:accountID:expiresAt:)`, `OpenAIUsageProvider(authReader:httpClient:baseURL:warningThreshold:criticalThreshold:)`, `ProviderRegistry.makeDefault(tokenReader:codexAuthReader:httpClient:claudeBaseURL:openAIBaseURL:)`, `ThresholdCrossing(provider:limit:threshold:)`, `UsageFormatter.compactLabel(for:)` are used with the same names in every task.
- The app target does not compile between Task 14 and Task 15; both are committed and verified together in Task 17.
