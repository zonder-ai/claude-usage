# Enhanced Features Design
**Date:** 2026-02-18
**Status:** Approved

## Overview

Add five new features to the AIUsageMonitor macOS menu bar app:
1. Last updated timestamp
2. Manual refresh button
3. Smooth progress bar animation
4. Usage history sparkline chart (last 5 hours)
5. Token countdown (tokens remaining, if API supports it)

## Architecture: Option B — New `UsageHistoryStore` service

Add one new file (`UsageHistoryStore.swift` in `Shared/Services/`) that handles the rolling 5-hour buffer. `UsageViewModel` coordinates it alongside the existing `UsageStore`. All other changes are small, focused additions.

---

## Data Layer

### New model: `UsageSnapshot`
```swift
public struct UsageSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let fiveHourUtilization: Double
    public let sevenDayUtilization: Double
}
```

### New service: `UsageHistoryStore`
- Persists a rolling array of `UsageSnapshot` entries to `UserDefaults` (App Group, same suite as `UsageStore`)
- Capped at 360 entries (~5 hours at 30s poll interval)
- Key: `"usageHistory"`
- Methods: `append(_ snapshot: UsageSnapshot)`, `load() -> [UsageSnapshot]`, `trim(olderThan:)`

### `UsageViewModel` additions
- `lastUpdated: Date?` — set after each successful fetch
- `history: [UsageSnapshot]` — published, populated from `UsageHistoryStore`
- After each successful fetch: append snapshot, save to history store, trim to 5-hour window
- `historyStore: UsageHistoryStore` — injected, defaults to shared instance

### Token counts
- Extend `UsageWindow` to optionally decode `tokens_used: Int?` and `tokens_limit: Int?`
- First inspect raw API response to confirm field names
- If fields absent: hide token row entirely (no fallback UI)

---

## View Layer

### `UsageDropdownView` layout
```
┌─────────────────────────────────────┐
│  Claude Usage          ↻  [spinner] │  ← refresh button; spinner inside when loading
│                                     │
│  5-hour  ████████░░  78%           │  ← animated ProgressView
│          Resets in 1h 12m           │
│                                     │
│  7-day   ███░░░░░░░  34%           │  ← animated ProgressView
│          Resets in 4d 2h            │
│                                     │
│  ┌─ 5-hour trend (last 5h) ───────┐ │
│  │  ╱╲  ╱╲___╱╲                  │ │  ← Charts sparkline, no axes
│  └───────────────────────────────┘ │
│                                     │
│  Tokens remaining: 42,000 / 100,000 │  ← hidden if API doesn't return counts
│                                     │
│  Updated 23s ago                    │  ← live-ticking, caps at ">5m ago"
│  ─────────────────────────────────  │
│  ⚙ Settings…                       │
│  ⏻ Quit                             │
│  ─────────────────────────────────  │
│         powered by [logo] zonder.ai │
└─────────────────────────────────────┘
```

### Animation
- `withAnimation(.easeInOut(duration: 0.4))` wraps utilization value changes in `UsageRowView`
- `ProgressView` value driven by `@State` animated property

### Sparkline chart
- `Charts` framework (`import Charts`) — available macOS 13+
- `LineMark` with `x: .value("Time", snapshot.timestamp)`, `y: .value("Usage", snapshot.fiveHourUtilization)`
- No axis labels; subtle area fill; color matches `UsageLevel`
- Hidden when `history.count < 2`

### Refresh button
- `Button { viewModel.fetchUsage() }` with `↻` SF Symbol (`arrow.clockwise`)
- `.disabled(viewModel.isLoading)`
- Spinner replaces icon when loading (conditional swap)

### Last updated timestamp
- `TimelineView(.periodic(from: .now, by: 1))` or a 1s `Timer` in the view
- Formats as: "Updated Xs ago" / "Updated Xm ago" / "Updated >5m ago"

---

## Error Handling & Edge Cases

| Scenario | Behaviour |
|---|---|
| Token counts missing from API | Token row hidden entirely |
| History empty on first launch | Sparkline hidden until ≥2 data points |
| History persistence across restarts | Saved to App Group `UserDefaults` |
| Manual refresh while loading | Button disabled during `isLoading` |
| "Updated ago" staleness | Caps display at ">5m ago" |

---

## Files Changed

| File | Change |
|---|---|
| `Shared/Models/UsageData.swift` | Add optional `tokensUsed`, `tokensLimit` to `UsageWindow`; add `UsageSnapshot` model |
| `Shared/Services/UsageHistoryStore.swift` | **New** — rolling 360-entry buffer |
| `Shared/UsageViewModel.swift` | Add `lastUpdated`, `history`, `historyStore`; append snapshot on fetch |
| `AIUsageMonitor/Views/UsageDropdownView.swift` | Refresh button, animated bars, sparkline, token row, timestamp |
