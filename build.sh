#!/bin/zsh
# Builds a universal (Apple Silicon + Intel), sandboxed, hardened-runtime MacPad.app.
# Signs ad hoc by default; set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.
set -euo pipefail
cd "$(dirname "$0")"

# Build each architecture separately and merge them: SwiftPM's multi-arch mode needs full Xcode.
BINARIES=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0"
    BINARIES+=("$(swift build -c release --triple "$ARCH-apple-macosx13.0" --show-bin-path)/MacPad")
done

APP=MacPad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create $BINARIES -output "$APP/Contents/MacOS/MacPad"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --timestamp=none \
    --entitlements Resources/MacPad.entitlements --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $PWD/$APP"
