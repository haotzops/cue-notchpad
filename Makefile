SHELL := /bin/bash

# Version used by release-asset targets when RELEASE_VERSION is not given.
# build-release.sh requires an explicit version for the archive name; the
# same source of truth as build-app.sh keeps the default effortless.
CURRENT_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Supporting/Info.plist)

.PHONY: tokenizer build build-release test app app-release release install install-app-release install-preview install-release install-published-release uninstall clean

tokenizer:
	./Scripts/generate-tokenizer-index.py

build: tokenizer
	swift build

build-release: tokenizer
	swift build -c release

test: tokenizer
	swift test
	swift run cue-core-tests

app: tokenizer
	CONFIGURATION=debug ./Scripts/build-app.sh

app-release: tokenizer
	CONFIGURATION=release ./Scripts/build-app.sh

release: tokenizer
	./Scripts/build-release.sh

install:
	CONFIGURATION=debug ./Scripts/install.sh

install-app-release:
	CONFIGURATION=release ./Scripts/install.sh

# Local preflight for real release assets: build the same ZIP as the release
# pipeline (build-release.sh), verify its digest, then install from that ZIP.
# Version defaults to Supporting/Info.plist; override with RELEASE_VERSION=.
install-preview:
	RELEASE_VERSION="$(or $(RELEASE_VERSION),$(CURRENT_VERSION))" BUILD_NUMBER="$(or $(BUILD_NUMBER),1)" ./Scripts/build-release.sh
	cd dist && shasum -a 256 -c SHA256SUMS
	RELEASE_ARCHIVE="dist/Cue-Notchpad-$(or $(RELEASE_VERSION),$(CURRENT_VERSION))-macOS-arm64.zip" ./Scripts/install.sh

install-release:
	@test -n "$(RELEASE_ARCHIVE)" || { echo 'Usage: make install-release RELEASE_ARCHIVE=/path/to/release.zip' >&2; exit 2; }
	RELEASE_ARCHIVE="$(RELEASE_ARCHIVE)" ./Scripts/install.sh

install-published-release:
	@test -n "$(VERSION)" || { echo 'Usage: make install-published-release VERSION=x.y.z' >&2; exit 2; }
	VERSION="$(VERSION)" ./Scripts/install-published-release.sh

uninstall:
	./Scripts/uninstall.sh

clean:
	rm -rf .build build dist
