#!/bin/sh
# Assembles dnotes.app from the SwiftPM binary. Signing and notarization are out of
# scope (design §11) — this is a personal build.
set -eu

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"

swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/dnotes"

APP="dnotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/dnotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The app icon is generated from the single 1024px source rather than committed as a
# binary .icns, so there is one thing to edit when the artwork changes. This is the
# Finder/notification icon only — the menu bar item draws its own template glyph in
# code (see MenuBarIcon.swift), because artwork this dark and detailed cannot serve
# as a template image.
# images/icon_dock.png is the squircle tile — the shape macOS app icons take — while
# images/icon.png is the earlier free-standing book, kept for reference.
ICON_SOURCE="images/icon_dock.png"
if [ -f "$ICON_SOURCE" ]; then
    ICONSET="$(swift build -c "$CONFIGURATION" --show-bin-path)/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"

    # The artwork sits in the middle of its canvas with a wide transparent border —
    # the tile is only 63% of 1024px — which the Dock renders as a small icon with
    # nothing around it. frame-icon crops that border away and refits, bringing the
    # tile to ~92%. It exists because the crop has to be *offset*: the visible pixels
    # sit above the canvas centre, and sips can only crop centred.
    FRAMED="$ICONSET/../icon-framed.png"
    swift scripts/frame-icon.swift "$ICON_SOURCE" "$FRAMED" 1024 1.0

    while read -r size name; do
        [ -n "$name" ] || continue
        sips -z "$size" "$size" "$FRAMED" --out "$ICONSET/$name.png" >/dev/null
    done <<EOF
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
EOF
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: $ICON_SOURCE missing — bundling without an app icon" >&2
fi

# An unsigned bundle that macOS has seen before keeps its old identity and starts
# getting called damaged; a fresh ad-hoc signature avoids that. This is not
# distribution signing — that needs a Developer ID certificate, which this machine
# does not have (§11). To hand the app to someone else, replace `-` with the
# certificate's identity and add an `xcrun notarytool submit` step.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
echo "run it with: open $APP"
