SHELL := /bin/bash

.PHONY: tokenizer build build-release test app app-release release install install-app-release install-release install-published-release uninstall clean

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
