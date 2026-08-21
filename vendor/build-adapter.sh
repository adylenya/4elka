#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/mediaremote-adapter"
OUT="$ROOT/build"
FW="$OUT/MediaRemoteAdapter.framework"

# Проверяем наличие .git и клонируем через временный каталог с атомарным
# переносом: иначе прерванное на середине клонирование оставит существующий,
# но неполный каталог, следующий запуск его молча пропустит и упадёт уже
# на clang, требуя ручной чистки.
if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC" "$SRC.partial"
  git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git "$SRC.partial"
  mv "$SRC.partial" "$SRC"
fi

rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources"

clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 \
  -I"$SRC/include" -I"$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$FW/Versions/A/MediaRemoteAdapter" \
  "$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST

ln -sfn A "$FW/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FW/Resources"
codesign --force --deep --sign - "$FW"

echo "готово: $FW"
