#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DeepL-oFM.app"
if [ ! -d "$APP" ]; then
    echo "Run ./build.sh first / Спочатку запустіть ./build.sh" >&2
    exit 1
fi
if ! command -v create-dmg >/dev/null; then
    echo "Install create-dmg with Homebrew / Встановіть create-dmg через Homebrew" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
stage="$(mktemp -d "$PWD/build/dmg.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/files"
ditto "$APP" "$stage/files/DeepL-oFM.app"
swift Scripts/make-dmg-background.swift "$stage"
tiffutil -cathidpicheck "$stage/background-1x.tiff" "$stage/background-2x.tiff" \
    -out "$stage/Installer.tiff"

create-dmg \
    --no-internet-enable --volname "DeepL-oFM" \
    --volicon "$APP/Contents/Resources/AppIcon.icns" \
    --background "$stage/Installer.tiff" \
    --window-pos 120 110 --window-size 660 416 \
    --icon-size 112 --text-size 16 \
    --icon "DeepL-oFM.app" 180 208 --hide-extension "DeepL-oFM.app" \
    --app-drop-link 480 208 \
    "$stage/DeepL-oFM.dmg" "$stage/files"

hdiutil verify "$stage/DeepL-oFM.dmg"
mv -f "$stage/DeepL-oFM.dmg" build/DeepL-oFM.dmg
echo "Created build/DeepL-oFM.dmg / Створено build/DeepL-oFM.dmg"
