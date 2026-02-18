# Menu Bar Style Picker Design
**Date:** 2026-02-19
**Status:** Approved

## Overview

Add a user-selectable menu bar display style. Three options available via a new "Menu Bar Style" section in Settings. All styles show the Claude logo on the left.

## Styles

| Style | Appearance | Description |
|---|---|---|
| `percentage` | `[logo] 42%` | Current default — logo + rounded percentage |
| `circle` | `[logo] [○]` | Logo + circular progress ring, color-coded |
| `bar` | `[logo] [████░░]` | Logo + 50px horizontal progress bar, color-coded |

## Architecture: `@AppStorage` in views (Option A)

Persist via `@AppStorage("menuBarStyle")` directly in `AIUsageApp` and `SettingsView`. No changes to `UsageViewModel`. SwiftUI handles UserDefaults automatically.

---

## Data Layer

New `MenuBarStyle` enum in `Shared` (accessible to both app and settings targets):

```swift
public enum MenuBarStyle: String, CaseIterable {
    case percentage  // default
    case circle
    case bar
}
```

File: `Shared/Models/MenuBarStyle.swift` (new file, must be added to project.pbxproj)

---

## View Layer

### `AIUsageApp.swift`

Add `@AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage`.

Switch on `menuBarStyle` inside the `MenuBarExtra` label:

- **percentage**: existing `HStack { logo + Text(menuBarText) }`
- **circle**: `HStack { logo + CircleProgressView(utilization, color) }` — 14×14pt ring drawn with two `Circle` strokes, trimmed by utilization fraction, rotated -90°
- **bar**: `HStack { logo + BarProgressView(utilization, color) }` — 50×6pt rounded rect with colored fill overlay

`CircleProgressView` and `BarProgressView` are private helper views defined in `AIUsageApp.swift`.

### `SettingsView.swift`

Add `@AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage`.

New `Section("Menu Bar Style")` inserted between General and Notifications:

```
Picker("Style", selection: $menuBarStyle) {
    Label("Percentage",  systemImage: "percent")      .tag(MenuBarStyle.percentage)
    Label("Circle",      systemImage: "circle.dotted").tag(MenuBarStyle.circle)
    Label("Bar",         systemImage: "slider.horizontal.3").tag(MenuBarStyle.bar)
}
.pickerStyle(.radioGroup)
```

Bump `defaultSize` height: 300 → 360 to accommodate the new section.

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| No data yet | Circle/bar show empty (0%) state, same as `--% ` for percentage |
| Usage > 100% | Clamped to 1.0 via `min(..., 1.0)` |
| Settings window height | `defaultSize` bumped to 360 |

---

## Files Changed

| File | Change |
|---|---|
| `Shared/Models/MenuBarStyle.swift` | **New** — `MenuBarStyle` enum |
| `AIUsageMonitor.xcodeproj/project.pbxproj` | Add new file to Shared target |
| `AIUsageMonitor/AIUsageApp.swift` | `@AppStorage`, label switch, helper views |
| `AIUsageMonitor/Views/SettingsView.swift` | New section + picker, height bump |
