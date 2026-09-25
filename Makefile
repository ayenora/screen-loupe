.PHONY: help build run test test-one format lint preflight clean version icon release

PROJECT := ScreenLoupe.xcodeproj
SCHEME := ScreenLoupe
CONFIGURATION ?= Debug
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(SCHEME).app
DESTINATION := platform=macOS,arch=$(shell uname -m)

# Source roots swift-format walks. Only the ones that exist, so format/lint
# stay usable before the Xcode project is created.
APP_DIR := ScreenLoupe
TESTS_DIR := ScreenLoupeTests
SWIFT_DIRS := $(wildcard $(APP_DIR) $(TESTS_DIR))

BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)

# make release: a signed, notarized Developer ID DMG (docs/internal/release.md, Channel A).
RELEASE_DIR := build/release
NOTARY_PROFILE := screenloupe-notary
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-configuration $(CONFIGURATION) -destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA) -quiet \
	CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

help:
	@echo "Available targets:"
	@echo "  make build      - Debug build into $(DERIVED_DATA)"
	@echo "  make run        - Build and open the app"
	@echo "  make test       - Run the whole unit-test suite"
	@echo "  make test-one T=ScreenLoupeTests/SomeTests[/'someTest()']"
	@echo "                  - Run one test class or method"
	@echo "  make format     - Format Swift sources in place (swift-format)"
	@echo "  make lint       - Lint Swift sources, warnings are errors"
	@echo "  make preflight  - format, lint, build, test (the push gate)"
	@echo "  make clean      - Remove build/"
	@echo "  make version    - Show marketing version and build number"
	@echo "  make icon       - Redraw the app icon (scripts/make_icon.swift)"
	@echo "  make release    - Archive, sign with Developer ID, notarize: build/release/*.dmg"
	@echo ""
	@echo "Variables: CONFIGURATION=Debug|Release (default Debug)"

build:
	$(XCODEBUILD) build

run: build
	open "$(APP)"

test:
	@since=$$(date +%s); $(XCODEBUILD) test || { python3 scripts/test_failures.py $$since; exit 1; }

test-one:
ifndef T
	$(error Pass the test id: make test-one T=ScreenLoupeTests/SomeTests[/testSomething])
endif
	@since=$$(date +%s); $(XCODEBUILD) test '-only-testing:$(T)' || { python3 scripts/test_failures.py $$since; exit 1; }

format:
ifeq ($(SWIFT_DIRS),)
	@echo "No Swift sources yet — nothing to format."
else
	xcrun swift-format format --in-place --recursive --parallel $(SWIFT_DIRS)
endif

lint:
ifeq ($(SWIFT_DIRS),)
	@echo "No Swift sources yet — nothing to lint."
else
	xcrun swift-format lint --strict --recursive --parallel $(SWIFT_DIRS)
endif

preflight: format lint build test

clean:
	rm -rf build

version:
	@echo "Marketing version: $$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION =/ {print $$3; exit}')"
	@echo "Build number:      $(BUILD_NUMBER)"

icon:
	swift scripts/make_icon.swift ScreenLoupe/Resources/Assets.xcassets/AppIcon.appiconset

# The build number is the commit count, so a release builds a clean, committed tree. The copies
# made on the way are unregistered and the staging folders removed, so only the DMG and the archive
# stay and macOS doesn't offer extra copies of the app.
release:
	@test -z "$$(git status --porcelain)" || { echo "Commit first: the build number is the commit count."; exit 1; }
	@version=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION =/ {print $$3; exit}'); \
	dmg=$(RELEASE_DIR)/ScreenLoupe-$$version.dmg; \
	set -e; \
	rm -rf $(RELEASE_DIR); \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -quiet \
		-archivePath $(RELEASE_DIR)/ScreenLoupe.xcarchive CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive; \
	xcodebuild -exportArchive -quiet -allowProvisioningUpdates -archivePath $(RELEASE_DIR)/ScreenLoupe.xcarchive \
		-exportOptionsPlist scripts/ExportOptions.plist -exportPath $(RELEASE_DIR)/export; \
	mkdir -p $(RELEASE_DIR)/dmg; \
	cp -R $(RELEASE_DIR)/export/$(SCHEME).app $(RELEASE_DIR)/dmg/; \
	ln -s /Applications $(RELEASE_DIR)/dmg/Applications; \
	hdiutil create -quiet -volname "Screen Loupe" -srcfolder $(RELEASE_DIR)/dmg -ov -format UDZO $$dmg; \
	codesign --sign "Developer ID Application" --timestamp $$dmg; \
	xcrun notarytool submit $$dmg --keychain-profile $(NOTARY_PROFILE) --wait; \
	xcrun stapler staple $$dmg; \
	spctl -a -vvv -t install $$dmg; \
	$(LSREGISTER) -u $(RELEASE_DIR)/export/$(SCHEME).app $(RELEASE_DIR)/dmg/$(SCHEME).app \
		$(RELEASE_DIR)/ScreenLoupe.xcarchive/Products/Applications/$(SCHEME).app; \
	rm -rf $(RELEASE_DIR)/export $(RELEASE_DIR)/dmg; \
	echo "Ready: $$dmg (version $$version, build $(BUILD_NUMBER))"
