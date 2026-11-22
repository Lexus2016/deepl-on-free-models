#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building DeepL-oFM (release)"
swift build -c release

APP="build/DeepL-oFM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/HyMT "$APP/Contents/MacOS/DeepL-oFM"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Embedding Sparkle"
SPARKLE_FRAMEWORK=".build/out/Products/Release/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=$(find .build -type d -name "Sparkle.framework" | head -1)
fi
if [ -z "$SPARKLE_FRAMEWORK" ] || [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework not found. Run 'swift build -c release' first." >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/DeepL-oFM" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/DeepL-oFM"
fi

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
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
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
    # Hardened runtime and a secure timestamp are required for notarization.
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    echo "    no signing identity found; using ad-hoc signing"
    echo "    TCC (Accessibility) may ask again after every rebuild."
    codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Signature verified"

echo "==> Done: $APP"
