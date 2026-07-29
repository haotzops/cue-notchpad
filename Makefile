.PHONY: tokenizer build test app release install clean

tokenizer:
	./Scripts/generate-tokenizer-index.py

build: tokenizer
	swift build

test: tokenizer
	swift run cue-core-tests

app:
	./Scripts/build-app.sh

release:
	./Scripts/build-release.sh

install:
	./Scripts/install.sh

clean:
	rm -rf .build build dist
