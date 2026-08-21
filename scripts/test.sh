#!/bin/bash
# Обвязка вокруг swift test. На машине стоят только Command Line Tools:
# модуля XCTest в них нет вовсе, а Testing.framework есть, но SwiftPM не знает
# путей до него и до его lib_TestingInterop.dylib. Подставляем их, выводя из
# xcode-select, поэтому Xcode не нужен. Аргументы пробрасываются насквозь,
# так что ./scripts/test.sh --filter ИмяТеста работает.
set -euo pipefail

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [ ! -d "$FW/Testing.framework" ]; then
  echo "не найден Testing.framework в $FW — тесты запускать нечем" >&2
  exit 1
fi

exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" \
  "$@"
