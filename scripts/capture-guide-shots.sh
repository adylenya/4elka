#!/bin/bash
# Съёмка снимков для руководства. Запускать ТОЛЬКО по явному «го» владельца:
# приложение рисуется на настоящем экране, а скрипт пишет в буфер обмена.
#
# Всё, что можно снять без человека, снимается само. Два снимка требуют его
# руки — меню в строке меню и окно настроек открываются только щелчком.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/guide/images"
BIN="$ROOT/.build/debug/Chelka"
mkdir -p "$OUT"

# Кадр под челкой: только верхняя полоса по центру, чтобы в снимок не попадали
# чужие окна и личное. Ширина экрана берётся у системы, а не задаётся числом.
WIDTH=$(system_profiler SPDisplaysDataType -json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['SPDisplaysDataType'][0]['spdisplays_ndrvs'][0]['_spdisplays_pixels'].split(' x ')[0])" 2>/dev/null || echo 2056)
STRIP_W=900
STRIP_X=$(( (WIDTH / 2) - (STRIP_W / 2) ))

say() { printf '\n=== %s\n' "$1"; }

[ -x "$BIN" ] || { echo "Сначала собери: swift build"; exit 1; }

# Гасим свой прошлый экземпляр, если остался. Только по пути своей сборки:
# широкий шаблон совпадает и с процессами компилятора.
kill -9 $(ps -eo pid,command | awk -v b="$BIN" '$0 ~ b {print $1}') 2>/dev/null || true

say "Запускаю приложение"
"$BIN" >/tmp/4elka-capture.log 2>&1 &
APP=$!
trap 'kill -9 $APP 2>/dev/null || true; echo "Приложение погашено."' EXIT
sleep 3

say "Снимок 2: челка в покое"
screencapture -x -R "$STRIP_X,0,$STRIP_W,180" "$OUT/02-notch-idle.png"

say "Снимок 3: карточка после копирования текста"
printf 'Заметка, которую я только что скопировал' | pbcopy
screencapture -x -T 1 -R "$STRIP_X,0,$STRIP_W,180" "$OUT/03-card-text.png"
sleep 3

say "Снимок 4: карточка после снимка экрана"
screencapture -c -R "100,300,500,300"
screencapture -x -T 1 -R "$STRIP_X,0,$STRIP_W,180" "$OUT/04-card-image.png"
sleep 3

say "Снимок 5: раскрытая панель"
osascript -e 'tell application "System Events" to keystroke "v" using {control down, option down}'
sleep 1
screencapture -x -R "$STRIP_X,0,$STRIP_W,420" "$OUT/05-panel.png"
osascript -e 'tell application "System Events" to keystroke "v" using {control down, option down}'

say "Снимок 1: НУЖНА ТВОЯ РУКА — щёлкни иконку 4elka в строке меню, чтобы меню раскрылось"
echo "    Снимок будет сделан через 8 секунд."
screencapture -x -T 8 -R "$(( WIDTH - 700 )),0,700,260" "$OUT/01-menu.png"

say "Снимок 7: НУЖНА ТВОЯ РУКА — открой «Настройки…» и щёлкни по окну настроек"
echo "    Курсор станет фотоаппаратом: щёлкни по окну настроек."
screencapture -o -w "$OUT/07-settings.png"

say "Готово. Что получилось:"
ls -la "$OUT"
