SHELL := /bin/bash
.DEFAULT_GOAL := help

CURRENT_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Supporting/Info.plist)
RELEASE_VERSION ?= $(CURRENT_VERSION)
BUILD_NUMBER ?= 1
DIST_DIR ?= dist
BUILT_RELEASE_ARCHIVE := $(DIST_DIR)/Cue-Notchpad-$(RELEASE_VERSION)-macOS-arm64.zip

.PHONY: help tokenizer check-source check build test app release-preflight install install-rc install-release uninstall clean

help:
	@printf '%s\n' \
		'Local development:' \
		'  make check                    Validate sources, build debug products, and run tests' \
		'  make app                      Build the debug app in build/' \
		'  make install                  Build and install the debug app' \
		'' \
		'Local Release candidate (never publishes):' \
		'  make release-preflight  Run checks, then build and verify release assets once' \
		'  make install-rc         Run preflight and install the resulting candidate' \
		'' \
		'Published Release reproduction:' \
		'  make install-release VERSION=x.y.z' \
		'' \
		'Publishing is performed only by the v*.*.* tag workflow; see Docs/releasing.md.'

tokenizer:
	./Scripts/generate-tokenizer-index.py

check-source:
	./Scripts/check-source.sh

check: check-source build test

build: tokenizer
	swift build

test: tokenizer
	node --experimental-strip-types --test Tests/PiIntegration/index.test.mjs
	swift run cue-tests

app:
	CONFIGURATION=debug ./Scripts/build-app.sh

# This is the shared pre-publication gate used locally, in CI, and by the tag
# workflow. It creates candidate assets but never uploads or publishes them.
release-preflight: check
	RELEASE_VERSION="$(RELEASE_VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" DIST_DIR="$(DIST_DIR)" ./Scripts/build-release.sh
	RELEASE_VERSION="$(RELEASE_VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" DIST_DIR="$(DIST_DIR)" ./Scripts/verify-release-package.sh

install:
	CONFIGURATION=debug ./Scripts/install.sh

install-rc:
	$(MAKE) release-preflight
	RELEASE_ARCHIVE="$(BUILT_RELEASE_ARCHIVE)" ./Scripts/install.sh

install-release:
	@test -n "$(VERSION)" || { echo 'Usage: make install-release VERSION=x.y.z' >&2; exit 2; }
	VERSION="$(VERSION)" ./Scripts/install-published-release.sh

uninstall:
	./Scripts/uninstall.sh

clean:
	rm -rf .build build dist
