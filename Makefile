.PHONY: build test app install clean

build:
	swift build

test:
	swift run cue-core-tests

app:
	./Scripts/build-app.sh

install:
	./Scripts/install.sh

clean:
	rm -rf .build build
