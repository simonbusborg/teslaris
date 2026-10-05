APP     = Teslaris.app
# Universal builds land under .build/apple, not .build/release.
BINARY  = .build/apple/Products/Release/Teslaris
DMG     = Teslaris.dmg

# Code-signing identity. Default "-" is ad-hoc (local builds); CI passes a
# "Developer ID Application: …" identity for notarized releases.
IDENTITY ?= -

# Team ID, used only to prefix the App Group identifier — on macOS a group
# has to be <TEAM>.group.…, unlike iOS. It's a secret in CI. A build without
# it still assembles and signs; its widget reads from a plain folder instead
# (see scripts/make-entitlements.sh). Never pass it to an ad-hoc build: a
# group claimed without a team in the signature resolves and then denies
# every read.
TEAM_ID ?=
APP_GROUP = $(if $(TEAM_ID),$(TEAM_ID).group.com.weareheavy.teslaris,)

# Read from the app's Info.plist so the extension can never claim a different
# version from the app containing it — `make release` bumps one file. Not
# named VERSION: that is the argument `make release` insists on being given.
APP_VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP_BUILD   = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)

# The widget extension, hand-assembled like the app bundle around it.
WIDGET  = $(APP)/Contents/PlugIns/TeslarisWidget.appex
WIDGET_BINARY = .build/apple/Products/Release/TeslarisWidget
# Generated entitlements; see the `entitlements` target.
ENT     = build

# Where SwiftPM unpacked Sparkle's xcframework. The version is in the path,
# so it's found rather than hard-coded.
SPARKLE = $(shell find .build/artifacts -type d -name Sparkle.framework -path '*macos*' | head -1)

# Sparkle ships helpers that are separately-signed code in their own right:
# two XPC services, an Updater.app and the Autoupdate tool. Every one of them
# has to be signed before the framework is, and each has to actually exist —
# an earlier version of this quietly skipped missing paths and the notary
# service rejected the build for unsigned nested code.
SIGN_NESTED = scripts/sign-sparkle.sh $(APP)

.PHONY: build app dmg run test mock clean release entitlements install

## Build the release binary as a universal (Apple silicon + Intel) binary.
## CI runs on an arm64 runner, so a plain `swift build` ships an arm64-only
## app that Intel Macs refuse to launch — the icon gets the prohibitory
## overlay and looks like a Gatekeeper block. TeslarisShared is a static
## library target, linked into this one binary; the bundle gains no files.
build:
	swift build -c release --arch arm64 --arch x86_64

## The app and the widget are signed with different entitlements, and both
## depend on whether there is a Team ID to build an App Group from.
entitlements:
	scripts/make-entitlements.sh $(ENT) "$(APP_GROUP)"

## Assemble a proper .app bundle (needed for launch-at-login) and sign it
app: build entitlements
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/Teslaris
	# Fail here, not on an Intel Mac, if the build ever stops being universal.
	lipo $(APP)/Contents/MacOS/Teslaris -verify_arch arm64 x86_64
	# The app reads back the App Group it was signed with rather than
	# hard-coding a Team ID, so the identifier is substituted here.
	sed -e 's|__APP_GROUP__|$(APP_GROUP)|' \
		Resources/Info.plist > $(APP)/Contents/Info.plist
	cp Resources/Teslaris.icns $(APP)/Contents/Resources/Teslaris.icns
	# The widget is a second executable dropped into PlugIns as an .appex.
	# Its Info.plist carries the same App Group, and the app's own version:
	# the system caches a widget per version, so one that drifted from the
	# app kept being offered in its old form.
	mkdir -p $(WIDGET)/Contents/MacOS
	cp $(WIDGET_BINARY) $(WIDGET)/Contents/MacOS/TeslarisWidget
	lipo $(WIDGET)/Contents/MacOS/TeslarisWidget -verify_arch arm64 x86_64
	sed -e 's|__APP_GROUP__|$(APP_GROUP)|' \
		-e 's|__VERSION__|$(APP_VERSION)|' \
		-e 's|__BUILD__|$(APP_BUILD)|' \
		Resources/TeslarisWidget-Info.plist > $(WIDGET)/Contents/Info.plist
	# SwiftPM links Sparkle but won't embed it — an executable target has no
	# bundle to embed into. The framework is copied by hand and the binary
	# gets an rpath pointing at it, or the app dies at launch with "Library
	# not loaded".
	mkdir -p $(APP)/Contents/Frameworks
	cp -R "$(SPARKLE)" $(APP)/Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP)/Contents/MacOS/Teslaris
	# Nested code is signed first and the outer bundle last: signing the app
	# seals the frameworks' signatures, so doing it the other way round
	# invalidates them. --deep is Apple-discouraged and does the wrong thing
	# with Sparkle's XPC services.
	# The .appex is nested code too, so it is signed before the app that
	# contains it — and with its own entitlements, because the extension is
	# sandboxed while Teslaris is not.
ifeq ($(IDENTITY),-)
	codesign --force --entitlements $(ENT)/TeslarisWidget.entitlements -s - $(WIDGET)
	@$(SIGN_NESTED) --force -s -
	codesign --force -s - $(APP)/Contents/Frameworks/Sparkle.framework
	codesign --force --entitlements $(ENT)/Teslaris.entitlements -s - $(APP)
else
	codesign --force --options runtime --timestamp --entitlements $(ENT)/TeslarisWidget.entitlements -s "$(IDENTITY)" $(WIDGET)
	@$(SIGN_NESTED) --force --options runtime --timestamp -s "$(IDENTITY)"
	codesign --force --options runtime --timestamp -s "$(IDENTITY)" $(APP)/Contents/Frameworks/Sparkle.framework
	codesign --force --options runtime --timestamp --entitlements $(ENT)/Teslaris.entitlements -s "$(IDENTITY)" $(APP)
endif
	codesign --verify --deep --strict --verbose=2 $(APP)
	@echo "Done → open $(APP)  (or move it to /Applications)"

## Package the existing bundle as a drag-to-Applications disk image.
## Deliberately NOT dependent on `app`: that target is phony, and re-running
## it in CI after notarization would re-sign the bundle and void the staple.
dmg:
	@test -d $(APP) || { echo "No $(APP) — run 'make app' first"; exit 1; }
	rm -rf dmg-staging $(DMG)
	mkdir dmg-staging
	cp -R $(APP) dmg-staging/
	ln -s /Applications dmg-staging/Applications
	hdiutil create -volname Teslaris -srcfolder dmg-staging -ov -format UDZO $(DMG)
	rm -rf dmg-staging
	@echo "Done → $(DMG)"

## Build and put it in /Applications, replacing what's there. The system
## keeps a cached copy of a widget extension, so the widget host is
## restarted too — without that a rebuilt widget keeps showing the old one.
install: app
	-killall Teslaris 2>/dev/null
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/
	-killall chronod 2>/dev/null
	open /Applications/$(APP)

## Quick run without a bundle (launch-at-login disabled in this mode).
## Named explicitly so adding another executable target can't make it
## ambiguous.
run:
	swift run Teslaris

test:
	swift test

## Local mock Fleet API for end-to-end testing without a car
mock:
	python3 mock-server/mock_fleet_api.py

clean:
	rm -rf .build $(ENT) $(APP) $(DMG) dmg-staging

## Cut a release: make release VERSION=0.2.0
## Bumps Info.plist, commits, tags v0.2.0, pushes — GitHub Actions then
## builds, packages and publishes the DMG/zip. Same process as Polaris.
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION must be x.y.z"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "working tree not clean"; exit 1; }
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Resources/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$(( $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist) + 1 ))" Resources/Info.plist
	git commit -am "Release v$(VERSION)"
	git tag "v$(VERSION)"
	git push origin HEAD "v$(VERSION)"
	@echo "Done → GitHub Actions is building the release"
