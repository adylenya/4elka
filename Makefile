.PHONY: adapter test build run clean app install uninstall

adapter:
	bash vendor/build-adapter.sh

test:
	bash scripts/test.sh

build:
	swift build

run:
	swift run Chelka

probe-player:
	@echo "==> пробник плеера: только чтение, музыку не трогает"
	@# Копия под именем main.swift: код верхнего уровня Swift разрешает только там.
	@mkdir -p /tmp/4elka-probe && cp tools/player-probe.swift /tmp/4elka-probe/main.swift
	@swiftc -swift-version 6 -O -o /tmp/4elka-probe/run /tmp/4elka-probe/main.swift $$(find Sources/ChelkaCore -name "*.swift")
	@cd . && /tmp/4elka-probe/run

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
