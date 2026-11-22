#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building HyMT (release)"
swift build -c release

APP="build/HyMT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/HyMT "$APP/Contents/MacOS/HyMT"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Rendering icon"
mkdir -p build
swift Scripts/make-icon.swift

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" build/icon-master.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
# Retina variants expected by iconutil
cp "$ICONSET/icon_16x16.png"     "$ICONSET/icon_16x16@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_32x32@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_128x128.png"   "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true
iconutil -c icns "$ICONSET" -o build/AppIcon.icns
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
IDENTITY="${HYMT_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
fi

if [ -n "$IDENTITY" ]; then
    echo "    identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "    no signing identity found; using ad-hoc signing"
    echo "    TCC (Accessibility) may ask again after every rebuild."
    codesign --force --deep --sign - "$APP"
fi

echo "==> Done: $APP"
