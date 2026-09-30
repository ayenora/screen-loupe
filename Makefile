.PHONY: help build run test test-one format lint preflight clean version icon release appstore

# This file's folder, empty when make runs here: scripts and configuration are found from it, so the
# targets also work from a Makefile in another folder that includes this one.
ROOT := $(patsubst ./%,%,$(dir $(lastword $(MAKEFILE_LIST))))

PROJECT ?= $(ROOT)ScreenLoupe.xcodeproj
SCHEME ?= ScreenLoupe
CONFIGURATION ?= Debug
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(SCHEME).app
DESTINATION := platform=macOS,arch=$(shell uname -m)

# Source roots swift-format walks. Only the ones that exist, so format/lint
# stay usable before the Xcode project is created.
APP_DIR := $(ROOT)ScreenLoupe
TESTS_DIR := $(ROOT)ScreenLoupeTests
SWIFT_DIRS ?= $(wildcard $(APP_DIR) $(TESTS_DIR))
SWIFT_FORMAT_CONFIG := $(ROOT).swift-format

# The commit count. A Makefile that includes this one, or the command line, may set another; the
# environment may not, so a variable left in it can't change what a build is numbered.
ifneq ($(origin BUILD_NUMBER),file)
ifneq ($(origin BUILD_NUMBER),command line)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
endif
endif
MARKETING_VERSION = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION =/ {print $$3; exit}')

# make release: a signed, notarized Developer ID DMG, kept with its archive in build/release/<version>/;
# make appstore: the App Store package from the same archive, in build/release/<version>/appstore/.
RELEASE_DIR := build/release
NOTARY_PROFILE := screenloupe-notary
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-configuration $(CONFIGURATION) -destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA) -quiet \
	CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

# The unit tests are this folder's project's: run from here, into this folder's build/, numbered by
# its own commits, whichever Makefile includes this one.
TESTS_HOME := $(or $(ROOT),.)
TESTS_BUILD_NUMBER := $(if $(ROOT),$(shell git -C $(ROOT) rev-list --count HEAD 2>/dev/null || echo 0),$(BUILD_NUMBER))
TESTS_XCODEBUILD := xcodebuild -project ScreenLoupe.xcodeproj -scheme ScreenLoupe \
	-configuration $(CONFIGURATION) -destination '$(DESTINATION)' \
	-derivedDataPath build/DerivedData -quiet \
	CURRENT_PROJECT_VERSION=$(TESTS_BUILD_NUMBER)

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
	@echo "  make release    - Archive, sign with Developer ID, notarize: build/release/<version>/"
	@echo "  make appstore   - Export the version's archive for App Store Connect: build/release/<version>/appstore/"
	@echo ""
	@echo "Variables: CONFIGURATION=Debug|Release (default Debug)"

build:
	$(XCODEBUILD) build

run: build
	open "$(APP)"

test:
	@cd $(TESTS_HOME) && since=$$(date +%s) && { $(TESTS_XCODEBUILD) test || { python3 scripts/test_failures.py $$since; exit 1; }; }

test-one:
ifndef T
	$(error Pass the test id: make test-one T=ScreenLoupeTests/SomeTests[/testSomething])
endif
	@cd $(TESTS_HOME) && since=$$(date +%s) && { $(TESTS_XCODEBUILD) test '-only-testing:$(T)' || { python3 scripts/test_failures.py $$since; exit 1; }; }

format:
ifeq ($(SWIFT_DIRS),)
	@echo "No Swift sources yet — nothing to format."
else
	xcrun swift-format format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel $(SWIFT_DIRS)
endif

lint:
ifeq ($(SWIFT_DIRS),)
	@echo "No Swift sources yet — nothing to lint."
else
	xcrun swift-format lint --configuration $(SWIFT_FORMAT_CONFIG) --strict --recursive --parallel $(SWIFT_DIRS)
endif

preflight: format lint build test

clean:
	rm -rf build

version:
	@echo "Marketing version: $(MARKETING_VERSION)"
	@echo "Build number:      $(BUILD_NUMBER)"

icon:
	swift $(ROOT)scripts/make_icon.swift $(ROOT)ScreenLoupe/Resources/Assets.xcassets/AppIcon.appiconset

# The build number is the commit count, so a release builds a clean, committed tree. The copies
# made on the way are unregistered and the staging folders removed, so only the DMG and the archive
# stay and macOS doesn't offer extra copies of the app. Each version has its own folder, so an
# earlier release's archive stays for its App Store upload and crash symbols.
release::
	@test -z "$$(git status --porcelain)" || { echo "Commit first: the build number is the commit count."; exit 1; }
	@version=$(MARKETING_VERSION); \
	dir=$(RELEASE_DIR)/$$version; \
	dmg=$$dir/ScreenLoupe-$$version.dmg; \
	set -e; \
	rm -rf $$dir; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -quiet \
		-archivePath $$dir/ScreenLoupe.xcarchive CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive; \
	xcodebuild -exportArchive -quiet -allowProvisioningUpdates -archivePath $$dir/ScreenLoupe.xcarchive \
		-exportOptionsPlist $(ROOT)scripts/ExportOptions.plist -exportPath $$dir/export; \
	mkdir -p $$dir/dmg; \
	cp -R $$dir/export/$(SCHEME).app $$dir/dmg/; \
	ln -s /Applications $$dir/dmg/Applications; \
	hdiutil create -quiet -volname "Screen Loupe" -srcfolder $$dir/dmg -ov -format UDZO $$dmg; \
	codesign --sign "Developer ID Application" --timestamp $$dmg; \
	xcrun notarytool submit $$dmg --keychain-profile $(NOTARY_PROFILE) --wait; \
	xcrun stapler staple $$dmg; \
	spctl -a -vvv -t install $$dmg; \
	$(LSREGISTER) -u $$dir/export/$(SCHEME).app $$dir/dmg/$(SCHEME).app \
		$$dir/ScreenLoupe.xcarchive/Products/Applications/$(SCHEME).app; \
	rm -rf $$dir/export $$dir/dmg; \
	echo "Ready: $$dmg (version $$version, build $(BUILD_NUMBER))"

# The App Store gets the DMG's archive, so both have the same binary and build number. Without one,
# the version is archived first; an archive of another build number is refused: run make release.
appstore::
	@test -z "$$(git status --porcelain)" || { echo "Commit first: the build number is the commit count."; exit 1; }
	@version=$(MARKETING_VERSION); \
	dir=$(RELEASE_DIR)/$$version; \
	archive=$$dir/ScreenLoupe.xcarchive; \
	set -e; \
	if [ ! -d $$archive ]; then \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -quiet \
			-archivePath $$archive CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive; \
	fi; \
	built=$$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' $$archive/Info.plist); \
	test "$$built" = "$(BUILD_NUMBER)" || { echo "$$archive is build $$built, not $(BUILD_NUMBER): run make release."; exit 1; }; \
	rm -rf $$dir/appstore; \
	xcodebuild -exportArchive -quiet -allowProvisioningUpdates -archivePath $$archive \
		-exportOptionsPlist $(ROOT)scripts/ExportOptions-AppStore.plist -exportPath $$dir/appstore; \
	$(LSREGISTER) -u $$archive/Products/Applications/$(SCHEME).app; \
	echo "Ready: $$dir/appstore (version $$version, build $(BUILD_NUMBER)); upload the .pkg with Transporter"
