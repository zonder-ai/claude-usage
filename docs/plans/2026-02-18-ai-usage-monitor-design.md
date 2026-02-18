# AI Usage Monitor — Design Document

## Overview

A macOS menu bar app that tracks Claude subscription usage (5-hour and 7-day limits) in real-time, with color-coded status and threshold notifications.

## Scope

- **In scope**: Claude Pro/Max subscription usage tracking, menu bar percentage display, dropdown detail panel, notifications at thresholds, OAuth authentication (Keychain shortcut + browser fallback)
- **Out of scope (v1)**: ChatGPT Plus tracking (no official API), desktop widget (future), external device integration (future)
- **Future-proofed**: App Group + shared data target for easy WidgetKit addition later

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI with `MenuBarExtra` (macOS 13+)
- **Target**: macOS 13 Ventura and later
- **Build**: Xcode project

## Architecture

```
AIUsageMonitor/
├── AIUsageMonitor/              # Main menu bar app target
│   ├── AIUsageApp.swift         # App entry point with MenuBarExtra
│   ├── Views/
│   │   ├── UsageDropdownView.swift  # Dropdown panel UI
│   │   └── SettingsView.swift       # Notification preferences
│   └── App/
│       └── AppDelegate.swift        # Notification setup, app lifecycle
├── Shared/                      # Shared framework target (App Group)
│   ├── Models/
│   │   └── UsageData.swift          # Usage data models
│   ├── Services/
│   │   ├── ClaudeAPIClient.swift    # HTTP calls to usage API
│   │   ├── AuthManager.swift        # Keychain + OAuth token management
│   │   └── UsageStore.swift         # Shared UserDefaults persistence
│   └── UsageViewModel.swift         # ObservableObject, polling logic
└── (future: WidgetExtension/)
```

### App Group

Shared data container: `group.com.aiusagemonitor`
Used by `UsageStore` to write usage data to shared `UserDefaults`, enabling a future WidgetKit extension to read the same data.

## API Integration

### Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
```

### Headers

```
Authorization: Bearer {accessToken}
anthropic-beta: oauth-2025-04-20
Content-Type: application/json
Accept: application/json
```

### Response

```json
{
  "five_hour": {
    "utilization": 72.0,
    "resets_at": "2026-02-18T15:59:59.943648+00:00"
  },
  "seven_day": {
    "utilization": 35.0,
    "resets_at": "2026-02-22T03:59:59.943679+00:00"
  }
}
```

### Polling

Every 30 seconds via a Swift `Timer`.

## Authentication

### Flow (ordered by priority)

1. Check macOS Keychain for `"Claude Code-credentials"` entry
2. If found, extract `claudeAiOauth.accessToken` from the stored JSON
3. If not found, trigger `ASWebAuthenticationSession` OAuth flow against `console.anthropic.com/oauth/authorize`
4. Store obtained token in the app's own Keychain entry
5. Handle token refresh when expired (using `refreshToken`)

## Menu Bar Display

### Status Text

Format: `C: 72%` — shows the higher of 5-hour or 7-day utilization.

### Color Coding

| Range   | Color  | Meaning           |
|---------|--------|--------------------|
| 0-60%   | Green  | Normal usage       |
| 60-85%  | Yellow | Approaching limit  |
| 85-100% | Red    | Near/at limit      |

## Dropdown Panel

```
Claude Usage
─────────────────────────
5-hour    ████████░░  72%
          Resets in 2h 13m

7-day     ███░░░░░░░  35%
          Resets in 4d 2h
─────────────────────────
⚙ Settings...
⏻ Quit
```

## Notifications

- Uses `UNUserNotificationCenter`
- Default thresholds: 75%, 90%, 100%
- Configurable in Settings
- Each threshold fires only once per reset cycle (tracked via reset timestamp)
- Separate tracking for 5-hour and 7-day windows

## Future Considerations

- **Desktop Widget**: Add a WidgetKit extension target that reads from the shared App Group. Requires `TimelineProvider` and a small SwiftUI widget view.
- **ChatGPT Plus**: Blocked on OpenAI providing a subscription usage API. Architecture supports adding new providers to `ClaudeAPIClient` (rename to generic `UsageAPIClient` when needed).
- **External LED Display**: Add an optional local HTTP server exposing `/status` JSON on localhost for LAN devices to consume.
