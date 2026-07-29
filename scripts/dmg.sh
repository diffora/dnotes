#!/bin/sh
# Packages dnotes.app into a disk image for a release.
#
# The image is ad-hoc signed like the app inside it, not notarized, because
# distribution signing needs a Developer ID certificate this project does not have
# (design §11). macOS quarantines anything downloaded, so whoever opens this has to
# clear the quarantine flag once — the release notes say how. There is no way around
# that short of a certificate.
set -eu

cd "$(dirname "$0")/.."
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

./scripts/bundle.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dnotes.app "$STAGE/"
# The customary drag-to-install target.
ln -s /Applications "$STAGE/Applications"

DMG="dnotes-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
    -volname "dnotes $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
