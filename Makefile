SCHEME      = AIUsageMonitor
PROJECT     = AIUsageMonitor.xcodeproj
CONFIG      = Release
APP_NAME    = ZonderClaudeUsage.app
VERSION    ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

SIGN_TEAM   = X77R7CFNAY
SIGN_ID    ?= Developer ID Application: GUILLERMO DEL OLMO FERNANDEZ VALDES (X77R7CFNAY)

SCRIPT_DIR      = scripts/release
PREFLIGHT       = $(SCRIPT_DIR)/preflight.sh
CHECK_SPARKLE   = $(SCRIPT_DIR)/check-sparkle-signatures.sh
NOTARIZE_SCRIPT = $(SCRIPT_DIR)/notarize.sh
VERIFY_ARTIFACT = $(SCRIPT_DIR)/verify-artifact.sh

ZIP_PATH     = release/ZonderClaudeUsage-$(VERSION).zip
SIGN_UPDATE  = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update -type f 2>/dev/null | head -1)
BUILT_APP_CMD = find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1

.PHONY: build install uninstall release notarize appcast

build:
	@$(PREFLIGHT) --mode build --sign-id "$(SIGN_ID)" --version "$(VERSION)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="$(SIGN_ID)" \
		CODE_SIGN_STYLE=Manual \
		DEVELOPMENT_TEAM=$(SIGN_TEAM) \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		ENABLE_HARDENED_RUNTIME=YES \
		build
	$(eval BUILT_APP := $(shell $(BUILT_APP_CMD)))
	@test -n "$(BUILT_APP)" && test -d "$(BUILT_APP)" || { echo "Build output not found: $(APP_NAME)"; exit 1; }
	@$(PREFLIGHT) --mode build --sign-id "$(SIGN_ID)" --version "$(VERSION)" --built-app "$(BUILT_APP)"
	codesign --force --deep --options runtime --timestamp --sign "$(SIGN_ID)" "$(BUILT_APP)"

install: build
	$(eval BUILT_APP := $(shell $(BUILT_APP_CMD)))
	pkill -f ZonderClaudeUsage 2>/dev/null; sleep 1; true
	rm -rf "/Applications/$(APP_NAME)"
	cp -R "$(BUILT_APP)" "/Applications/$(APP_NAME)"
	xattr -dr com.apple.quarantine "/Applications/$(APP_NAME)"
	open "/Applications/$(APP_NAME)"
	@echo "✓ Installed and launched /Applications/$(APP_NAME)"

uninstall:
	pkill -f ZonderClaudeUsage 2>/dev/null; true
	rm -rf "/Applications/$(APP_NAME)"
	@echo "✓ Removed /Applications/$(APP_NAME)"

release:
	@$(PREFLIGHT) --mode release --sign-id "$(SIGN_ID)" --version "$(VERSION)"
	@$(MAKE) build VERSION=$(VERSION)
	$(eval BUILT_APP := $(shell $(BUILT_APP_CMD)))
	@test -n "$(BUILT_APP)" && test -d "$(BUILT_APP)" || { echo "Build output not found: $(APP_NAME)"; exit 1; }
	@$(CHECK_SPARKLE) --app "$(BUILT_APP)" --team "$(SIGN_TEAM)"
	@mkdir -p release
	@rm -f "$(ZIP_PATH)"
	ditto -c -k --keepParent "$(BUILT_APP)" "$(ZIP_PATH)"
	@$(VERIFY_ARTIFACT) --zip "$(ZIP_PATH)" --expect pre-notary
	@echo "✓ Created $(ZIP_PATH)"

notarize:
	@$(PREFLIGHT) --mode notarize --sign-id "$(SIGN_ID)" --version "$(VERSION)" --zip "$(ZIP_PATH)"
	$(eval BUILT_APP := $(shell $(BUILT_APP_CMD)))
	@$(NOTARIZE_SCRIPT) --zip "$(ZIP_PATH)" --app "$(BUILT_APP)" --team "$(SIGN_TEAM)"
	@$(VERIFY_ARTIFACT) --zip "$(ZIP_PATH)" --expect notarized
	@echo "✓ Notarized and validated $(ZIP_PATH)"

appcast:
	@$(PREFLIGHT) --mode appcast --sign-id "$(SIGN_ID)" --version "$(VERSION)" --zip "$(ZIP_PATH)"
	@$(VERIFY_ARTIFACT) --zip "$(ZIP_PATH)" --expect notarized
	@test -n "$(SIGN_UPDATE)" || { echo "Error: sign_update not found. Build the project first to fetch Sparkle."; exit 1; }
	$(eval SIG_OUTPUT := $(shell "$(SIGN_UPDATE)" "$(ZIP_PATH)"))
	$(eval ED_SIG := $(shell echo '$(SIG_OUTPUT)' | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p'))
	$(eval LENGTH := $(shell echo '$(SIG_OUTPUT)' | sed -n 's/.*length="\([^"]*\)".*/\1/p'))
	$(eval PUB_DATE := $(shell date -R))
	@echo '<?xml version="1.0" standalone="yes"?>' > appcast.xml
	@echo '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">' >> appcast.xml
	@echo '    <channel>' >> appcast.xml
	@echo '        <title>ZonderClaudeUsage</title>' >> appcast.xml
	@echo '        <item>' >> appcast.xml
	@echo '            <title>Version $(VERSION)</title>' >> appcast.xml
	$(eval BUNDLE_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" AIUsageMonitor/Info.plist))
	@echo '            <sparkle:version>$(BUNDLE_VERSION)</sparkle:version>' >> appcast.xml
	@echo '            <sparkle:shortVersionString>$(VERSION)</sparkle:shortVersionString>' >> appcast.xml
	@echo '            <pubDate>$(PUB_DATE)</pubDate>' >> appcast.xml
	@echo '            <enclosure' >> appcast.xml
	@echo '                url="https://github.com/zonder-ai/claude-usage/releases/download/$(VERSION)/ZonderClaudeUsage-$(VERSION).zip"' >> appcast.xml
	@echo '                sparkle:edSignature="$(ED_SIG)"' >> appcast.xml
	@echo '                length="$(LENGTH)"' >> appcast.xml
	@echo '                type="application/octet-stream"' >> appcast.xml
	@echo '            />' >> appcast.xml
	@echo '        </item>' >> appcast.xml
	@echo '    </channel>' >> appcast.xml
	@echo '</rss>' >> appcast.xml
	@echo "✓ Updated appcast.xml for $(VERSION)"
