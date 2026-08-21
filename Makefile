.PHONY: adapter test build run clean app install uninstall

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

app:
	bash scripts/make-app.sh

install: app
	rm -rf /Applications/4elka.app
	cp -R build/4elka.app /Applications/
	open /Applications/4elka.app

uninstall:
	osascript -e 'quit app "4elka"' || true
	rm -rf /Applications/4elka.app
