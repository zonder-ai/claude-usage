SCHEME     = AIUsageMonitor
PROJECT    = AIUsageMonitor.xcodeproj
CONFIG     = Release
APP_NAME   = ZonderClaudeUsage.app
VERSION   ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
BUILD_DIR  = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination "platform=macOS" -showBuildSettings CODE_SIGN_IDENTITY="-" 2>/dev/null | awk -F ' = ' '/BUILT_PRODUCTS_DIR/{print $$2}')

SIGN_UPDATE = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update -type f 2>/dev/null | head -1)

.PHONY: build install uninstall release appcast

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		build

install: build
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
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

release: build
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
	@mkdir -p release
	@rm -f "release/ZonderClaudeUsage-$(VERSION).zip"
	ditto -c -k --keepParent "$(BUILT_APP)" "release/ZonderClaudeUsage-$(VERSION).zip"
	@echo "✓ Created release/ZonderClaudeUsage-$(VERSION).zip"

appcast:
	@test -f "release/ZonderClaudeUsage-$(VERSION).zip" || { echo "Error: release/ZonderClaudeUsage-$(VERSION).zip not found. Run 'make release' first."; exit 1; }
	@test -n "$(SIGN_UPDATE)" || { echo "Error: sign_update not found. Build the project first to fetch Sparkle."; exit 1; }
	$(eval SIG_OUTPUT := $(shell "$(SIGN_UPDATE)" "release/ZonderClaudeUsage-$(VERSION).zip"))
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
