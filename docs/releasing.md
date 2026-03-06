# Releasing ZonderClaudeUsage

This is the canonical release flow.

## Prerequisites

- macOS with Xcode command line tools installed
- Developer ID certificate installed in Keychain:
  - `Developer ID Application: GUILLERMO DEL OLMO FERNANDEZ VALDES (X77R7CFNAY)`
- Sparkle private key already configured in the project (for appcast signing)

## Notarization authentication

Use one of these modes:

1. Environment variables (recommended)
2. Keychain profile fallback

### Option A: Environment variables (recommended)

```bash
export APPLE_ID="guillermodf17@gmail.com"
export APPLE_TEAM_ID="X77R7CFNAY"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

### Option B: Keychain profile fallback

```bash
export NOTARY_KEYCHAIN_PROFILE="AC_PASSWORD"
```

## One blessed release flow

From the repo root:

```bash
make release VERSION=v1.3.5
make notarize VERSION=v1.3.5
make appcast VERSION=v1.3.5
```

Then publish:

```bash
git add appcast.xml
git commit -m "chore: update appcast for v1.3.5"
git push origin main
git tag v1.3.5
git push origin v1.3.5
gh release create v1.3.5 "release/ZonderClaudeUsage-v1.3.5.zip" --title "v1.3.5" --notes "Release notes here"
```

## What each step validates

- `make release`
  - toolchain preflight
  - cert presence preflight
  - release build + top-level codesign
  - Sparkle nested binary signature validation (team + timestamp)
  - zip creation
  - pre-notary artifact validation
- `make notarize`
  - notary submit/wait/log on failure
  - staple + stapler validate
  - re-zip stapled app
  - post-notary artifact validation
- `make appcast`
  - requires notarized zip
  - regenerates `appcast.xml`

## Troubleshooting

### `dquote>` in terminal

You pasted smart quotes (`“` or `”`) instead of straight quotes (`"`).

Use straight ASCII quotes only. Example:

```bash
xcrun notarytool submit "release/ZonderClaudeUsage-v1.3.5.zip" --apple-id "guillermodf17@gmail.com" --team-id "X77R7CFNAY" --password "xxxx-xxxx-xxxx-xxxx" --wait
```

### `HTTP Error 429`

Apple notarization service is rate-limiting requests.

- Wait and retry after a short delay
- Avoid repeated rapid submits of the same artifact
- Use the scripted flow (`make notarize`) which includes retry handling

### Signing identity not found

Check installed certs:

```bash
security find-identity -v -p codesigning
```

If the Developer ID cert is missing, install it in Keychain and re-run.

### Sparkle nested signatures invalid

`make release` now fails before upload if nested Sparkle binaries are not properly signed.

Rebuild from clean state and verify your Developer ID identity/team is correct:

- Team ID must be `X77R7CFNAY`
- `SIGN_ID` in `Makefile` must match installed certificate CN exactly

### Wrong directory / zip not found

Use absolute path or `cd` to repo root first:

```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
```

Then run `make release` before `make notarize`.
