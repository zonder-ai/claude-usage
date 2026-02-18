SCHEME     = AIUsageMonitor
CONFIG     = Release
APP_NAME   = AIUsageMonitor.app
VERSION   ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
BUILD_DIR  = $(shell xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination "platform=macOS" -showBuildSettings CODE_SIGN_IDENTITY="-" 2>/dev/null | awk -F ' = ' '/BUILT_PRODUCTS_DIR/{print $$2}')

.PHONY: build install uninstall release

build:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		build

install: build
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
	pkill -f $(SCHEME) 2>/dev/null; sleep 1; true
	rm -rf "/Applications/$(APP_NAME)"
	cp -R "$(BUILT_APP)" "/Applications/$(APP_NAME)"
	xattr -dr com.apple.quarantine "/Applications/$(APP_NAME)"
	open "/Applications/$(APP_NAME)"
	@echo "✓ Installed and launched /Applications/$(APP_NAME)"

uninstall:
	pkill -f $(SCHEME) 2>/dev/null; true
	rm -rf "/Applications/$(APP_NAME)"
	@echo "✓ Removed /Applications/$(APP_NAME)"

release: build
	$(eval BUILT_APP := $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/AIUsageMonitor-*/Build/Products/Release -name "$(APP_NAME)" -maxdepth 1 2>/dev/null | head -1))
	@mkdir -p release
	@rm -f "release/AIUsageMonitor-$(VERSION).zip"
	ditto -c -k --keepParent "$(BUILT_APP)" "release/AIUsageMonitor-$(VERSION).zip"
	@echo "✓ Created release/AIUsageMonitor-$(VERSION).zip"
