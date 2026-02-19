# Menu Bar Style Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users pick one of three menu bar display styles (percentage, circle ring, horizontal bar) from a new Settings section, persisted via `@AppStorage`.

**Architecture:** Add a `MenuBarStyle: String, CaseIterable` enum to `Shared`; use `@AppStorage("menuBarStyle")` in both `AIUsageApp` (to switch the label) and `SettingsView` (to drive a radio-group picker). No changes to `UsageViewModel`.

**Tech Stack:** Swift, SwiftUI, `@AppStorage` (UserDefaults), XCTest

---

### Task 1: Create `MenuBarStyle` enum

**Files:**
- Create: `Shared/Models/MenuBarStyle.swift`
- Create: `AIUsageMonitorTests/MenuBarStyleTests.swift`
- Modify: `AIUsageMonitor.xcodeproj/project.pbxproj`

**Step 1: Write the failing tests**

Create `AIUsageMonitorTests/MenuBarStyleTests.swift`:

```swift
import XCTest
@testable import Shared

final class MenuBarStyleTests: XCTestCase {

    func testAllCasesExist() {
        let all = MenuBarStyle.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.percentage))
        XCTAssertTrue(all.contains(.circle))
        XCTAssertTrue(all.contains(.bar))
    }

    func testRawValuesAreStableStrings() {
        // rawValues are stored in UserDefaults — must never change
        XCTAssertEqual(MenuBarStyle.percentage.rawValue, "percentage")
        XCTAssertEqual(MenuBarStyle.circle.rawValue,     "circle")
        XCTAssertEqual(MenuBarStyle.bar.rawValue,        "bar")
    }

    func testRoundTripsViaRawValue() {
        for style in MenuBarStyle.allCases {
            XCTAssertEqual(MenuBarStyle(rawValue: style.rawValue), style)
        }
    }
}
```

**Step 2: Create `Shared/Models/MenuBarStyle.swift`**

```swift
import Foundation

/// Controls how usage is displayed in the macOS menu bar.
/// Raw values are persisted in UserDefaults via @AppStorage — do not change them.
public enum MenuBarStyle: String, CaseIterable {
    case percentage  // [logo] 42%
    case circle      // [logo] + circular progress ring
    case bar         // [logo] + horizontal progress bar
}
```

**Step 3: Add both new files to `AIUsageMonitor.xcodeproj/project.pbxproj`**

Read the pbxproj. Follow the exact same pattern used in Task 2 of the previous feature (UsageHistoryStore) — find how `UsageStore.swift` is registered for the Shared target and `UsageStoreTests.swift` for the test target, and mirror it for the two new files.

Generate 4 UUIDs:
```bash
for i in 1 2 3 4; do uuidgen | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]'; done
```

Add:
1. `PBXFileReference` for `MenuBarStyle.swift` (in `Shared/Models/` group)
2. `PBXBuildFile` for `MenuBarStyle.swift` → Shared target Sources phase
3. `PBXFileReference` for `MenuBarStyleTests.swift` (in `AIUsageMonitorTests/` group)
4. `PBXBuildFile` for `MenuBarStyleTests.swift` → test target Sources phase

**Step 4: Run tests**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|passed|Executed)" | tail -10
```

Expected: 3 new `MenuBarStyleTests` pass, all prior tests still pass (34 total + 3 new = 37).

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add Shared/Models/MenuBarStyle.swift AIUsageMonitorTests/MenuBarStyleTests.swift AIUsageMonitor.xcodeproj/project.pbxproj
git commit -m "feat: add MenuBarStyle enum"
```

---

### Task 2: Update `AIUsageApp.swift` — label switcher + helper views

**Files:**
- Modify: `AIUsageMonitor/AIUsageApp.swift`

No new tests needed — this is pure SwiftUI view code. Verified by building and visually inspecting.

**Step 1: Read the current file**

Read `/Users/guilledelolmo/Documents/AI Usage App/AIUsageMonitor/AIUsageApp.swift`.

**Step 2: Replace the file**

Replace the entire file with:

```swift
import ServiceManagement
import Shared
import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.authManager.handleOAuthCallback(url: url)
                }
        } label: {
            HStack(spacing: 0) {
                Image(nsImage: {
                    let img = NSImage(named: "ClaudeLogo") ?? NSImage()
                    img.isTemplate = true
                    img.size = NSSize(width: 16, height: 16)
                    return img
                }())
                .foregroundStyle(viewModel.usageLevel.color)

                switch menuBarStyle {
                case .percentage:
                    Text(viewModel.menuBarText)
                        .monospacedDigit()
                        .padding(.leading, 6)
                case .circle:
                    CircleProgressView(
                        utilization: viewModel.usage?.fiveHour.utilization ?? 0,
                        color: viewModel.usageLevel.color
                    )
                    .padding(.leading, 4)
                case .bar:
                    BarProgressView(
                        utilization: viewModel.usage?.fiveHour.utilization ?? 0,
                        color: viewModel.usageLevel.color
                    )
                    .padding(.leading, 4)
                }
            }
            .task {
                viewModel.startPolling()
                if SMAppService.mainApp.status == .notRegistered {
                    try? SMAppService.mainApp.register()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 380, height: 360)
        .windowResizability(.contentSize)
    }
}

// MARK: - Circle progress ring (14×14 pt)

private struct CircleProgressView: View {
    let utilization: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(utilization / 100.0, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Horizontal progress bar (50×6 pt)

private struct BarProgressView: View {
    let utilization: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(utilization / 100.0, 1.0))
            }
        }
        .frame(width: 50, height: 6)
    }
}
```

**Step 3: Build**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
xcodebuild build -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' 2>&1 | grep -E "(FAILED|BUILD SUCCEEDED|error:)"
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add AIUsageMonitor/AIUsageApp.swift
git commit -m "feat: switch menu bar label based on MenuBarStyle preference"
```

---

### Task 3: Update `SettingsView.swift` — style picker section

**Files:**
- Modify: `AIUsageMonitor/Views/SettingsView.swift`

**Step 1: Read the current file**

Read `/Users/guilledelolmo/Documents/AI Usage App/AIUsageMonitor/Views/SettingsView.swift`.

**Step 2: Add `@AppStorage` and new section**

Make these changes to `SettingsView`:

1. Add after the existing `@State private var launchAtLogin` line:
```swift
@AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage
```

2. Add a new `Section("Menu Bar Style")` between the `Section("General")` and `Section("Notifications")` blocks:
```swift
Section("Menu Bar Style") {
    Picker("Style", selection: $menuBarStyle) {
        Label("Percentage", systemImage: "percent")
            .tag(MenuBarStyle.percentage)
        Label("Circle", systemImage: "circle.dotted")
            .tag(MenuBarStyle.circle)
        Label("Bar", systemImage: "slider.horizontal.3")
            .tag(MenuBarStyle.bar)
    }
    .pickerStyle(.radioGroup)
}
```

3. Update the frame height from `300` to `360`:
```swift
.frame(width: 380, height: 360)
```

**Step 3: Build and install**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
make install
```

Expected: Build succeeds, app installs to `/Applications/AIUsageMonitor.app`.

**Step 4: Verify manually**

- Open the app, click the menu bar icon
- Open Settings — confirm "Menu Bar Style" section appears with 3 radio options
- Switch to Circle — menu bar should show ring
- Switch to Bar — menu bar should show horizontal bar
- Switch back to Percentage — menu bar returns to `42%`
- Quit and relaunch — selected style persists

**Step 5: Commit**

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git add AIUsageMonitor/Views/SettingsView.swift
git commit -m "feat: add menu bar style picker to Settings"
```

---

### Task 4: Push

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
git push
```
