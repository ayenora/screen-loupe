.PHONY: help build run test test-one format lint preflight clean version icon

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
