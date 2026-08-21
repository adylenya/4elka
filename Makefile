.PHONY: adapter test build run app clean

adapter:
	bash vendor/build-adapter.sh

test:
	swift test

build:
	swift build

run:
	swift run Chelka

clean:
	rm -rf .build vendor/build build
