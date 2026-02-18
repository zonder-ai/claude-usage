SCHEME     = AIUsageMonitor
CONFIG     = Release
DERIVED    = $(HOME)/Library/Developer/Xcode/DerivedData
APP_NAME   = AIUsageMonitor.app
BUILD_DIR  = $(shell xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination "platform=macOS" -showBuildSettings CODE_SIGN_IDENTITY="-" 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $$3}')

.PHONY: build install uninstall

build:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		build

install: build
	pkill -f $(SCHEME) 2>/dev/null; sleep 1; true
	cp -Rf "$(BUILD_DIR)/$(APP_NAME)" "/Applications/$(APP_NAME)"
	xattr -dr com.apple.quarantine "/Applications/$(APP_NAME)"
	open "/Applications/$(APP_NAME)"
	@echo "✓ Installed and launched /Applications/$(APP_NAME)"

uninstall:
	pkill -f $(SCHEME) 2>/dev/null; true
	rm -rf "/Applications/$(APP_NAME)"
	@echo "✓ Removed /Applications/$(APP_NAME)"
