#!/bin/bash
# Собирает build/4elka.app — настоящий бандл, а не запуск из дерева разработки.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/4elka.app"
# Постоянный самоподписанный сертификат лучше разового: при разовой подписи она
# меняется на каждой сборке, и система считает приложение каждый раз новым —
# заново спрашивает разрешения и заново заводит элемент автозапуска.
# Задать свой: CHELKA_SIGN_IDENTITY="Имя сертификата" make app
IDENTITY="${CHELKA_SIGN_IDENTITY:--}"

echo "==> сборка в режиме release"
swift build -c release --package-path "$ROOT"

echo "==> сборка мостика к «сейчас играет»"
bash "$ROOT/vendor/build-adapter.sh"

echo "==> раскладка бандла"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/Chelka" "$APP/Contents/MacOS/Chelka"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ресурсные бандлы SwiftPM: без них ресурсы пакета внутри бандла не найдутся.
# Молча пропускаем, если их нет — сейчас пакет обходится без ресурсов.
find "$ROOT/.build/release" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

# Мостик к «сейчас играет». Приложение ищет его сначала в ресурсах бандла и
# только потом в дереве разработки — иначе установленная версия смотрела бы в
# чужой рабочий каталог, которого на другой машине нет.
cp -R "$ROOT/vendor/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
cp "$ROOT/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

# Лицензия чужого кода обязана лежать рядом с ним: mediaremote-adapter под
# BSD-3, и раздавать его без текста лицензии нельзя.
if [ -f "$ROOT/vendor/mediaremote-adapter/LICENSE" ]; then
  cp "$ROOT/vendor/mediaremote-adapter/LICENSE" "$APP/Contents/Resources/LICENSE-mediaremote-adapter"
else
  echo "!! не найден текст лицензии mediaremote-adapter — раздавать бандл нельзя" >&2
  exit 1
fi
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"

echo "==> подпись"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Resources/MediaRemoteAdapter.framework"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"

echo "готово: $APP"
