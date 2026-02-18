# Enhanced Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add last-updated timestamp, manual refresh, animated progress bars, 5-hour sparkline chart, and token countdown to the AIUsageMonitor menu bar app.

**Architecture:** Add `UsageSnapshot` model + optional token fields to `UsageData.swift`; create new `UsageHistoryStore` service for rolling 360-entry buffer; update `UsageViewModel` with `lastUpdated`, `history`, and `historyStore`; update `UsageDropdownView` with all new UI elements using the `Charts` framework.

**Tech Stack:** Swift, SwiftUI, Charts (macOS 13+ system framework), UserDefaults (App Group), XCTest

---

### Task 1: Add `UsageSnapshot` model and optional token fields to `UsageWindow`

**Files:**
- Modify: `Shared/Models/UsageData.swift`
- Modify: `AIUsageMonitorTests/UsageDataTests.swift`

**Step 1: Write the failing tests**

Add to `AIUsageMonitorTests/UsageDataTests.swift`:

```swift
func testUsageSnapshotEncodesAndDecodes() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let snapshot = UsageSnapshot(timestamp: now, fiveHourUtilization: 42.5, sevenDayUtilization: 18.0)
    let data = try JSONEncoder.apiEncoder.encode(snapshot)
    let decoded = try JSONDecoder.apiDecoder.decode(UsageSnapshot.self, from: data)
    XCTAssertEqual(decoded.fiveHourUtilization, 42.5)
    XCTAssertEqual(decoded.sevenDayUtilization, 18.0)
    XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
}

func testUsageWindowDecodesTokenFieldsWhenPresent() throws {
    let json = """
    {
        "utilization": 55.0,
        "resets_at": "2026-02-18T15:59:59.000000+00:00",
        "tokens_used": 55000,
        "tokens_limit": 100000
    }
    """.data(using: .utf8)!
    let window = try JSONDecoder.apiDecoder.decode(UsageWindow.self, from: json)
    XCTAssertEqual(window.tokensUsed, 55000)
    XCTAssertEqual(window.tokensLimit, 100000)
    XCTAssertEqual(window.tokensRemaining, 45000)
}

func testUsageWindowTokenFieldsNilWhenAbsent() throws {
    let json = """
    {
        "utilization": 55.0,
        "resets_at": "2026-02-18T15:59:59.000000+00:00"
    }
    """.data(using: .utf8)!
    let window = try JSONDecoder.apiDecoder.decode(UsageWindow.self, from: json)
    XCTAssertNil(window.tokensUsed)
    XCTAssertNil(window.tokensLimit)
    XCTAssertNil(window.tokensRemaining)
}
```

**Step 2: Run tests to verify they fail**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|error:|Build succeeded|Test Suite)"
```

Expected: compile error — `UsageSnapshot` not found.

**Step 3: Implement**

In `Shared/Models/UsageData.swift`, add after the `UsageWindow` struct:

```swift
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let fiveHourUtilization: Double
    public let sevenDayUtilization: Double

    public init(timestamp: Date, fiveHourUtilization: Double, sevenDayUtilization: Double) {
        self.timestamp = timestamp
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
    }
}
```

In `UsageWindow`, replace the existing struct with:

```swift
public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date
    public let tokensUsed: Int?
    public let tokensLimit: Int?

    public init(utilization: Double, resetsAt: Date, tokensUsed: Int? = nil, tokensLimit: Int? = nil) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.tokensUsed = tokensUsed
        self.tokensLimit = tokensLimit
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt    = "resets_at"
        case tokensUsed  = "tokens_used"
        case tokensLimit = "tokens_limit"
    }

    public var tokensRemaining: Int? {
        guard let used = tokensUsed, let limit = tokensLimit else { return nil }
        return max(0, limit - used)
    }

    public var timeUntilReset: TimeInterval {
        resetsAt.timeIntervalSinceNow
    }

    public var formattedTimeUntilReset: String {
        let remaining = max(0, timeUntilReset)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|passed|Build succeeded)"
```

Expected: all tests pass.

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add Shared/Models/UsageData.swift AIUsageMonitorTests/UsageDataTests.swift
git commit -m "feat: add UsageSnapshot model and optional token fields to UsageWindow"
```

---

### Task 2: Create `UsageHistoryStore`

**Files:**
- Create: `Shared/Services/UsageHistoryStore.swift`
- Create: `AIUsageMonitorTests/UsageHistoryStoreTests.swift`
- Modify: `AIUsageMonitor.xcodeproj/project.pbxproj` (add both files to their targets)

**Step 1: Write the failing tests**

Create `AIUsageMonitorTests/UsageHistoryStoreTests.swift`:

```swift
import XCTest
@testable import Shared

final class UsageHistoryStoreTests: XCTestCase {

    private func makeStore() -> (UsageHistoryStore, UserDefaults) {
        let suiteName = "test.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        return (UsageHistoryStore(defaults: defaults), defaults)
    }

    func testLoadReturnsEmptyWhenNothingSaved() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testAppendAndLoad() {
        let (store, _) = makeStore()
        let snap = UsageSnapshot(timestamp: Date(), fiveHourUtilization: 42.0, sevenDayUtilization: 18.0)
        store.append(snap)
        let history = store.load()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].fiveHourUtilization, 42.0)
    }

    func testTrimsEntriesOlderThanFiveHours() {
        let (store, _) = makeStore()
        let old = UsageSnapshot(timestamp: Date().addingTimeInterval(-6 * 3600),
                                fiveHourUtilization: 10.0, sevenDayUtilization: 5.0)
        let recent = UsageSnapshot(timestamp: Date(),
                                   fiveHourUtilization: 50.0, sevenDayUtilization: 20.0)
        store.append(old)
        store.append(recent)
        let history = store.load()
        // Old entry trimmed after appending recent
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].fiveHourUtilization, 50.0)
    }

    func testCapsAtMaxEntries() {
        let (store, _) = makeStore()
        // Append 365 entries (5 over the 360 cap), all recent
        for i in 0..<365 {
            let snap = UsageSnapshot(
                timestamp: Date().addingTimeInterval(TimeInterval(i * 30)),
                fiveHourUtilization: Double(i),
                sevenDayUtilization: 0
            )
            store.append(snap)
        }
        XCTAssertLessThanOrEqual(store.load().count, 360)
    }

    func testPersistsAcrossInstances() {
        let suiteName = "test.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }

        let store1 = UsageHistoryStore(defaults: defaults)
        store1.append(UsageSnapshot(timestamp: Date(), fiveHourUtilization: 77.0, sevenDayUtilization: 33.0))

        let store2 = UsageHistoryStore(defaults: defaults)
        XCTAssertEqual(store2.load().first?.fiveHourUtilization, 77.0)
    }
}
```

**Step 2: Create `Shared/Services/UsageHistoryStore.swift`**

```swift
import Foundation

public final class UsageHistoryStore: Sendable {
    private let defaults: UserDefaults
    private static let key = "usageHistory"
    private static let maxEntries = 360
    private static let maxAge: TimeInterval = 5 * 3600

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public convenience init() {
        let defaults = UserDefaults(suiteName: "group.com.aiusagemonitor") ?? .standard
        self.init(defaults: defaults)
    }

    public func append(_ snapshot: UsageSnapshot) {
        var history = load()
        history.append(snapshot)
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        history = history.filter { $0.timestamp > cutoff }
        if history.count > Self.maxEntries {
            history = Array(history.suffix(Self.maxEntries))
        }
        guard let data = try? JSONEncoder.apiEncoder.encode(history) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> [UsageSnapshot] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder.apiDecoder.decode([UsageSnapshot].self, from: data)) ?? []
    }
}
```

**Step 3: Add both files to the Xcode project**

Read `AIUsageMonitor.xcodeproj/project.pbxproj` to find:
- The UUID of the `Services` group (parent for `UsageHistoryStore.swift`)
- The UUID of the `AIUsageMonitorTests` group
- The Shared target's `PBXSourcesBuildPhase` UUID
- The test target's `PBXSourcesBuildPhase` UUID
- An existing Shared source file's PBXFileReference and PBXBuildFile entries to use as templates

Then add:
1. Two `PBXFileReference` entries (one for each new file)
2. Two `PBXBuildFile` entries
3. Add `UsageHistoryStore.swift` file reference to the `Services` group's `children` array
4. Add `UsageHistoryStoreTests.swift` file reference to the `AIUsageMonitorTests` group's `children` array
5. Add `UsageHistoryStore.swift` build file to Shared target's Sources build phase
6. Add `UsageHistoryStoreTests.swift` build file to test target's Sources build phase

Use 24-character uppercase hex UUIDs (e.g. generate with: `uuidgen | tr -d '-' | cut -c1-24`).

**Step 4: Run tests**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|passed|Build succeeded)"
```

Expected: all tests pass including the 5 new `UsageHistoryStoreTests`.

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add Shared/Services/UsageHistoryStore.swift AIUsageMonitorTests/UsageHistoryStoreTests.swift AIUsageMonitor.xcodeproj/project.pbxproj
git commit -m "feat: add UsageHistoryStore with rolling 5-hour buffer"
```

---

### Task 3: Update `UsageViewModel`

**Files:**
- Modify: `Shared/UsageViewModel.swift`
- Modify: `AIUsageMonitorTests/UsageViewModelTests.swift`

**Step 1: Update failing tests**

In `AIUsageMonitorTests/UsageViewModelTests.swift`:

1. Fix the stale `menuBarText` expectations (the "C:" prefix was removed — update `"C: --"` → `"--%"` and `"C: 72%"` → `"72%"` and `"C: 73%"` → `"73%"` and `"C: 10%"` → `"10%"`)

2. Add new tests:

```swift
func testLastUpdatedNilOnInit() {
    let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
    XCTAssertNil(vm.lastUpdated)
}

func testHistoryEmptyOnInit() {
    let suiteName = "test.vm.history.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    addTeardownBlock { defaults.removeSuite(named: suiteName) }
    let store = UsageHistoryStore(defaults: defaults)
    let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager(), historyStore: store)
    XCTAssertTrue(vm.history.isEmpty)
}

func testRecordSnapshotAppendsToHistory() {
    let suiteName = "test.vm.snap.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    addTeardownBlock { defaults.removeSuite(named: suiteName) }
    let store = UsageHistoryStore(defaults: defaults)
    let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager(), historyStore: store)

    let response = UsageResponse(
        fiveHour: .init(utilization: 42.0, resetsAt: Date()),
        sevenDay: .init(utilization: 18.0, resetsAt: Date())
    )
    vm.recordSnapshot(for: response)

    XCTAssertEqual(vm.history.count, 1)
    XCTAssertEqual(vm.history[0].fiveHourUtilization, 42.0)
    XCTAssertNotNil(vm.lastUpdated)
}
```

**Step 2: Run tests to see failures**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|error:|passed)"
```

Expected: failures for missing `historyStore` param and `recordSnapshot` method.

**Step 3: Update `Shared/UsageViewModel.swift`**

Add to the published properties section:
```swift
@Published public var lastUpdated: Date?
@Published public var history: [UsageSnapshot] = []
```

Add to the private properties section:
```swift
private let historyStore: UsageHistoryStore
```

Update `init` signature to include:
```swift
historyStore: UsageHistoryStore? = nil,
```

In `init` body, add after `self.store = store ?? UsageStore()`:
```swift
self.historyStore = historyStore ?? UsageHistoryStore()
self.history = self.historyStore.load()
```

Add new `internal` method (called from `fetchUsage` and tests):
```swift
func recordSnapshot(for response: UsageResponse) {
    let snapshot = UsageSnapshot(
        timestamp: Date(),
        fiveHourUtilization: response.fiveHour.utilization,
        sevenDayUtilization: response.sevenDay.utilization
    )
    historyStore.append(snapshot)
    history = historyStore.load()
    lastUpdated = Date()
}
```

In `fetchUsage()`, after `self.store.save(response)` and before `self.checkNotificationThresholds(response)`, add:
```swift
self.recordSnapshot(for: response)
```

**Step 4: Run tests**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|passed|Build succeeded)"
```

Expected: all tests pass.

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add Shared/UsageViewModel.swift AIUsageMonitorTests/UsageViewModelTests.swift
git commit -m "feat: add lastUpdated, history, and recordSnapshot to UsageViewModel"
```

---

### Task 4: Update `UsageDropdownView`

**Files:**
- Modify: `AIUsageMonitor/Views/UsageDropdownView.swift`

**Step 1: Add import and refresh button to header**

At the top of `UsageDropdownView.swift`, add `import Charts` after `import SwiftUI`.

Replace the header `HStack` (lines 10–18) with:

```swift
HStack {
    Text("Claude Usage")
        .font(.headline)
    Spacer()
    Button {
        viewModel.fetchUsage()
    } label: {
        if viewModel.isLoading {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
        }
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isLoading)
}
```

**Step 2: Add animated progress bars**

Replace `UsageRowView` with an animated version. In `UsageRowView`, add `@State private var animatedUtilization: Double = 0` and use `.onAppear` + `.onChange` to drive it:

Replace the entire `UsageRowView` struct with:

```swift
struct UsageRowView: View {
    let label: String
    let window: UsageWindow

    @State private var animatedUtilization: Double = 0

    private var level: UsageLevel { UsageLevel.from(utilization: window.utilization) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 52, alignment: .leading)

                ProgressView(value: min(animatedUtilization / 100.0, 1.0))
                    .tint(level.color)

                Text("\(Int(window.utilization.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(level.color)
                    .frame(width: 38, alignment: .trailing)
            }

            Text("Resets in \(window.formattedTimeUntilReset)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedUtilization = window.utilization
            }
        }
        .onChange(of: window.utilization) { newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedUtilization = newValue
            }
        }
    }
}
```

**Step 3: Add sparkline chart, token row, and timestamp to `UsageDropdownView`**

Replace the full `body` of `UsageDropdownView` with:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        // Header
        HStack {
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            Button {
                viewModel.fetchUsage()
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }

        if let errorMessage = viewModel.error {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .lineLimit(2)
        }

        if let usage = viewModel.usage {
            UsageRowView(label: "5-hour", window: usage.fiveHour)
            UsageRowView(label: "7-day", window: usage.sevenDay)
        } else if viewModel.error == nil {
            Text("Loading usage data…")
                .foregroundColor(.secondary)
                .font(.callout)
        }

        // Sparkline chart (5-hour trend)
        if viewModel.history.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Text("5-hour trend")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Chart(viewModel.history) { snapshot in
                    AreaMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("Usage", snapshot.fiveHourUtilization)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("Usage", snapshot.fiveHourUtilization)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 44)
            }
        }

        // Token countdown (only shown if API returns token counts)
        if let usage = viewModel.usage, let remaining = usage.fiveHour.tokensRemaining,
           let limit = usage.fiveHour.tokensLimit {
            HStack {
                Text("Tokens left:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(remaining.formatted()) / \(limit.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }

        // Last updated timestamp (live ticking)
        if let lastUpdated = viewModel.lastUpdated {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(formattedLastUpdated(lastUpdated))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }

        Divider()

        Button {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .buttonStyle(MenuRowButtonStyle())

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .buttonStyle(MenuRowButtonStyle())
        .keyboardShortcut("q")

        Divider()

        HStack(spacing: 5) {
            Text("powered by")
                .font(.caption2)
                .foregroundColor(.secondary)
            Image("ZonderLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text("zonder.ai")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
    .padding()
    .frame(width: 270)
}

private func formattedLastUpdated(_ date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    if elapsed < 60  { return "Updated \(Int(elapsed))s ago" }
    if elapsed < 300 { return "Updated \(Int(elapsed / 60))m ago" }
    return "Updated >5m ago"
}
```

Also make `UsageSnapshot` conform to `Identifiable` so `Chart(viewModel.history)` works. Add to `Shared/Models/UsageData.swift` the `Identifiable` conformance:

```swift
extension UsageSnapshot: Identifiable {
    public var id: Date { timestamp }
}
```

**Step 4: Build and install**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
make install
```

Expected: Build succeeds and app installs to `/Applications/AIUsageMonitor.app`.

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add AIUsageMonitor/Views/UsageDropdownView.swift Shared/Models/UsageData.swift
git commit -m "feat: add refresh button, animated bars, sparkline chart, token row, and timestamp to dropdown"
```

---

### Task 5: Push to remote

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git push
```
