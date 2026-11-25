PROJECT := auto-clicker.xcodeproj
SCHEME := auto-clicker
DERIVED_DATA ?= $(CURDIR)/build
PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products
DEBUG_APP := $(PRODUCTS_DIR)/Debug/AutoClicker.app
RELEASE_APP := $(PRODUCTS_DIR)/Release/AutoClicker.app

XCODEBUILD ?= xcodebuild
BUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) \
	-derivedDataPath $(DERIVED_DATA) -skipPackagePluginValidation

.DEFAULT_GOAL := help
.PHONY: build debug release test run run-debug path clean help

# Local debug build. This is the default when running plain `make`.
build debug:
	$(XCODEBUILD) $(BUILD_FLAGS) -configuration Debug build
	@printf '\nDebug app:\n%s\n' '$(DEBUG_APP)'

# Local release: use the development identity unless explicitly overridden.
# Override for distribution with RELEASE_SIGNING=... and, optionally, TEAM_ID=...
RELEASE_SIGNING ?= Apple Development
TEAM_ID ?= F9FV9SZH5Z
release:
	$(XCODEBUILD) $(BUILD_FLAGS) -configuration Release \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='$(RELEASE_SIGNING)' \
		DEVELOPMENT_TEAM='$(TEAM_ID)' build
	@printf '\nRelease app:\n%s\n' '$(RELEASE_APP)'

test:
	$(XCODEBUILD) $(BUILD_FLAGS) -configuration Debug test

# Do not leave the previous instance loading an older binary.
run: release
	@osascript -e 'tell application "AutoClicker" to quit' || true
	open -n '$(RELEASE_APP)'

run-debug: debug
	@osascript -e 'tell application "AutoClicker" to quit' || true
	open -n '$(DEBUG_APP)'

path:
	@printf 'Debug:   %s\nRelease: %s\n' '$(DEBUG_APP)' '$(RELEASE_APP)'

# Only removes the app's generated build directory.
clean:
	$(XCODEBUILD) $(BUILD_FLAGS) clean

help:
	@printf '%s\n' \
		'make / make debug  Compile Debug to build/Build/Products/Debug/AutoClicker.app' \
		'make release       Compile a locally signed Release build' \
		'make run           Build Release, close the old instance, and open the new app' \
		'make run-debug     Build and open Debug' \
		'make test          Run the unit test suite' \
		'make path          Print both app paths' \
		'make clean         Clean generated Xcode build files' \
		'' \
		'Distribution: make release RELEASE_SIGNING="Developer ID Application" TEAM_ID=...'
	git config core.hooksPath .githooks

# https://docs.fastlane.tools/getting-started/ios/setup/#use-a-gemfile
# https://docs.fastlane.tools/plugins/using-plugins/
# Keep dependency updates inside the user's Bundler environment. Never use sudo here:
# dependency scripts would otherwise run with root privileges.
.PHONY: update
update:
	bundle update fastlane
	bundle exec fastlane update_plugins

.PHONY: local
local:
	bundle exec fastlane mac local

.PHONY: beta
beta:
	bundle exec fastlane mac beta

.PHONY: prod
prod:
	bundle exec fastlane mac production
