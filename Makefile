# loadcli — build & release automation
SCHEME      := loadcli
PROJECT     := loadcli.xcodeproj
DERIVED     := build
DEBUG_APP   := $(DERIVED)/Build/Products/Debug/loadcli.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/loadcli.app

.PHONY: all bootstrap icon gen build run release sign-notarize dmg clean

all: build

## Install the build toolchain (Homebrew).
bootstrap:
	./scripts/bootstrap.sh

## Regenerate the app icon set procedurally.
icon:
	swift scripts/make_icon.swift

## Generate the Xcode project from project.yml.
gen:
	xcodegen generate

## Debug build (ad-hoc signed, with entitlements).
build: gen
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Debug -derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
		build | xcbeautify --quiet

## Build and launch.
run: build
	open $(DEBUG_APP)

## Release build. Signs with Developer ID if LOADCLI_SIGN_ID is set, else ad-hoc.
release: gen
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="$${LOADCLI_SIGN_ID:--}" \
		DEVELOPMENT_TEAM="$${LOADCLI_TEAM_ID:-}" \
		CODE_SIGN_STYLE=Manual \
		build | xcbeautify --quiet
	@echo "Built: $(RELEASE_APP)"

## Sign (Developer ID) + notarize + staple + build the DMG.
sign-notarize: release
	./scripts/sign_notarize.sh "$(RELEASE_APP)"

clean:
	rm -rf $(DERIVED) loadcli.xcodeproj dist
