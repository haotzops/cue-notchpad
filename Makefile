.PHONY: tokenizer build test app install clean

tokenizer:
	./Scripts/generate-tokenizer-index.py

build: tokenizer
	swift build

test: tokenizer
	swift run cue-core-tests

app:
	./Scripts/build-app.sh

install:
	./Scripts/install.sh

clean:
	rm -rf .build build
