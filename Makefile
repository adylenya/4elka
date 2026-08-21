.PHONY: adapter test build run clean

adapter:
	bash vendor/build-adapter.sh

test:
	bash scripts/test.sh

build:
	swift build

run:
	swift run Chelka

clean:
	rm -rf .build vendor/build build
