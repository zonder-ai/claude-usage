# ZonderClaudeUsage

A macOS menu bar app that shows your [Claude](https://claude.ai) usage in real time — 5-hour and 7-day windows with alerts when you're getting close to your limit.

![Menu bar showing Claude logo and 42%](docs/menubar.png)

## Features

- Live usage in the menu bar (5-hour window) — choose between percentage, circle ring, or horizontal bar
- Progress bars for both 5-hour and 7-day windows in the dropdown
- Color-coded levels (green → yellow → red)
- Notifications when usage crosses configurable thresholds (default: 50%, 75%, 90%, 100%)
- Picks up your existing Claude Code credentials automatically — no separate login needed in most cases
- Launches at login

## Requirements

- macOS 13 Ventura or later
- A Claude account (Pro or higher for usage limits to apply)

## Install

1. Download `ZonderClaudeUsage-vX.X.X.zip` from the [latest release](../../releases/latest)
2. Unzip and drag **ZonderClaudeUsage.app** to your `/Applications` folder
3. **First launch only:** right-click the app → **Open** (macOS requires this one-time step for apps without an Apple developer certificate)
4. **ZonderClaudeUsage** appears in your menu bar with the Zonder x Anthropic logo and your current usage

## Usage

- **Click the menu bar icon** to see the usage breakdown
- **Settings** — sign in with Claude OAuth if auto-detection didn't work, adjust notification thresholds, choose your menu bar style, toggle Launch at Login
- **Sign In** is only needed if you don't have Claude Code installed or the automatic Keychain read fails

## Updating

Download the new zip from [Releases](../../releases), replace the app in `/Applications`, relaunch.
No need for the right-click trick on updates — only the first install.

## Build from source

Requires Xcode 15+.

```bash
git clone https://github.com/zonder-ai/claude-usage.git
cd claude-usage
make install   # builds Release, copies to /Applications, launches
```

Other targets:

| Command | What it does |
|---|---|
| `make build` | Build only |
| `make install` | Build + copy to /Applications + launch |
| `make release VERSION=v1.2.0` | Build + create `release/ZonderClaudeUsage-v1.2.0.zip` |
| `make uninstall` | Quit + remove from /Applications |

## How authentication works

ZonderClaudeUsage needs an OAuth token to read your usage from `api.anthropic.com`. It tries these methods in order:

1. **Your app's own token** — if you've previously signed in via the app, it stores a token in your Keychain under `com.aiusagemonitor.oauth`.
2. **Refresh** — if the token is expired, it silently refreshes using the stored refresh token.
3. **Claude Code's Keychain** — if you have [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed, the app can read its Keychain entry (`Claude Code-credentials`). macOS will show a **one-time permission prompt** — you can click "Always Allow" or deny it and use the app's own Sign In instead.
4. **Browser OAuth** — click **Sign In** in Settings to authenticate via `claude.ai` with a standard PKCE flow.

No credentials are ever sent anywhere except Anthropic's own OAuth and API endpoints.

## Security and privacy

- **No App Sandbox** — the app runs unsandboxed because macOS sandboxing blocks cross-app Keychain access (needed for step 3 above). If you prefer, you can skip Claude Code keychain access entirely and sign in via the browser.
- **Tokens in Keychain** — OAuth tokens are stored in the macOS Keychain, not in plaintext files.
- **Usage data only** — the only data cached to disk (in UserDefaults) is usage percentages and timestamps. No personal information is stored.
- **Open source** — the full source is here for you to audit. The OAuth client ID in the code is a public identifier (not a secret).
