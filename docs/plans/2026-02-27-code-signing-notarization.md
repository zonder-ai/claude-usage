# Code Signing, Notarization & Touch ID — TODO

**Status:** Not started
**Context:** App is currently signed ad-hoc (`"-"`). Users get a Gatekeeper "unidentified developer" warning when downloading. Touch ID on system permission prompts and proper internet distribution both require a Developer ID cert + notarization.

---

## Current state

- Signing identity: `"-"` (ad-hoc, no real certificate)
- Hardened Runtime: not enabled
- Entitlements file: empty (`<dict/>`)
- No notarization
- Available cert: `Apple Development: guillermodf17@gmail.com` — this is for on-device testing only, not distribution

---

## Step 1 — Get a Developer ID Application certificate

1. Go to [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click **+** → choose **Developer ID Application**
3. Follow the CSR instructions, download the `.cer`, double-click to install in Keychain

Verify it's installed:
```bash
security find-identity -v -p codesigning
# Should show: "Developer ID Application: <your name> (<TEAM_ID>)"
```

---

## Step 2 — Store notarytool credentials

Get an **app-specific password** from [appleid.apple.com](https://appleid.apple.com) → Sign-In & Security → App-Specific Passwords.

Then store it once in the keychain (replace values with yours):
```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "guillermodf17@gmail.com" \
    --team-id "<YOUR_TEAM_ID>" \
    --password "<APP_SPECIFIC_PASSWORD>"
```

Your team ID is visible on developer.apple.com (top-right, under your name) or in the cert string above.

---

## Step 3 — Enable Hardened Runtime in Xcode

In Xcode → select the **AIUsageMonitor** target → **Signing & Capabilities** tab:
- Turn on **Hardened Runtime**

Or in the pbxproj build settings for Release config, add:
```
ENABLE_HARDENED_RUNTIME = YES;
```

---

## Step 4 — Update entitlements

The app reads `~/.claude/projects/*.jsonl` and makes HTTPS calls. No App Sandbox needed (Developer ID outside MAS doesn't require it). The entitlements file at `AIUsageMonitor/AIUsageMonitor.entitlements` should have at minimum:

```xml
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
```

If Hardened Runtime blocks file access to `~/.claude/` during testing, add:
```xml
<key>com.apple.security.files.all</key>
<true/>
```

---

## Step 5 — Update the Makefile

Replace the `SIGN_ID` and add a `notarize` target. The full updated `release` + `notarize` flow:

```makefile
SIGN_ID = "Developer ID Application: Guillermo De Lolmo (<TEAM_ID>)"

release: build
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
	@mkdir -p release
	@rm -f "release/ZonderClaudeUsage-$(VERSION).zip"
	ditto -c -k --keepParent "$(BUILT_APP)" "release/ZonderClaudeUsage-$(VERSION).zip"
	@echo "✓ Created release/ZonderClaudeUsage-$(VERSION).zip"

notarize:
	@test -f "release/ZonderClaudeUsage-$(VERSION).zip" || { echo "Run 'make release' first"; exit 1; }
	xcrun notarytool submit "release/ZonderClaudeUsage-$(VERSION).zip" \
		--keychain-profile "AC_PASSWORD" \
		--wait
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
	xcrun stapler staple "$(BUILT_APP)"
	@rm -f "release/ZonderClaudeUsage-$(VERSION).zip"
	ditto -c -k --keepParent "$(BUILT_APP)" "release/ZonderClaudeUsage-$(VERSION).zip"
	@echo "✓ Notarized and re-zipped release/ZonderClaudeUsage-$(VERSION).zip"
```

Also update the `build` target to use the real identity instead of `"-"`:
```makefile
	xcodebuild ... CODE_SIGN_IDENTITY=$(SIGN_ID) ...
```

---

## Step 6 — Updated publish flow

Once the above is done, the full release command becomes:
```bash
make release VERSION=v1.x.x
make notarize VERSION=v1.x.x
make appcast VERSION=v1.x.x
git add appcast.xml && git commit -m "chore: update appcast for v1.x.x" && git push
gh release create v1.x.x "release/ZonderClaudeUsage-v1.x.x.zip" --title "v1.x.x" --notes "..."
```

---

## Why this matters

- **Gatekeeper:** Without notarization, macOS shows "Apple cannot check it for malicious software" and users must right-click → Open. With notarization, the app opens normally.
- **Touch ID on permission prompts:** macOS automatically offers Touch ID on any system privacy dialog (Accessibility, Full Disk Access, etc.) for properly signed apps. No extra code needed.
- **Touch ID for in-app auth (optional):** If we want Touch ID to protect in-app actions (e.g. sign-out), that's a separate `LocalAuthentication` / `LAContext` implementation — can be added later.
