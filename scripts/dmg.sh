#!/bin/sh
# Packs build/Atomberg Console.app into build/Atomberg-Console-<version>.dmg with a SHA-256 file next to it.
# Run scripts/bundle.sh first. Needs only what macOS ships with.
set -eu
cd "$(dirname "$0")/.."

APP="build/Atomberg Console.app"
[ -d "$APP" ] || { printf 'dmg: run scripts/bundle.sh first\n' >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="build/Atomberg-Console-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Atomberg Console" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

printf '%s\n' "$PWD/$DMG"
cat "$DMG.sha256"
