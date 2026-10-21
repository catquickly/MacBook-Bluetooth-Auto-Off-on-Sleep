#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Auto Turn Off Bluetooth"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-turn-off-bluetooth-build.XXXXXX")"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

APP_ONLY=""
if [[ $# -gt 0 ]]; then
    if [[ $# -ne 2 || "$1" != "--app-only" || "$2" != /* ]]; then
        printf 'Usage: %s [--app-only /absolute/path/App.app]\n' "$0" >&2
        exit 2
    fi
    APP_ONLY="$2"
    [[ ! -e "$APP_ONLY" ]] || { printf 'Output already exists: %s\n' "$APP_ONLY" >&2; exit 1; }
fi

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Library/LaunchAgents" "$BUILD_DIR/module-cache"
COMMON=(-parse-as-library -swift-version 5 -O -target arm64-apple-macosx14.0
        -module-cache-path "$BUILD_DIR/module-cache"
        -framework AppKit -framework IOKit -framework IOBluetooth -framework ServiceManagement)
xcrun swiftc "${COMMON[@]}" -o "$CONTENTS/MacOS/HingeBluetooth" "$PROJECT_ROOT/Sources/HingeBluetooth/main.swift"
xcrun swiftc "${COMMON[@]}" -D HINGEBLUETOOTH_BACKGROUND_AGENT -o "$CONTENTS/Resources/HingeBluetoothAgent" "$PROJECT_ROOT/Sources/HingeBluetooth/main.swift"

cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/Resources/com.codex.hingebluetooth.agent.plist" "$CONTENTS/Library/LaunchAgents/"
cp -R "$PROJECT_ROOT/Resources/en.lproj" "$PROJECT_ROOT/Resources/zh-Hans.lproj" "$CONTENTS/Resources/"
cp "$PROJECT_ROOT/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
plutil -lint "$CONTENTS/Info.plist" "$CONTENTS/Library/LaunchAgents/com.codex.hingebluetooth.agent.plist"
for language in en zh-Hans; do
    plutil -lint "$CONTENTS/Resources/$language.lproj/Localizable.strings" "$CONTENTS/Resources/$language.lproj/InfoPlist.strings"
done

# Local ad-hoc signing only. No Developer ID credentials are required or stored.
codesign --force --sign - --options runtime "$CONTENTS/Resources/HingeBluetoothAgent"
codesign --force --sign - --options runtime "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -n "$APP_ONLY" ]]; then
    mkdir -p "$(dirname -- "$APP_ONLY")"
    ditto "$APP_BUNDLE" "$APP_ONLY"
    printf 'APP: %s\n' "$APP_ONLY"
else
    mkdir -p "$PROJECT_ROOT/releases"
    DMG_PATH="$PROJECT_ROOT/releases/$APP_NAME-$VERSION-arm64.dmg"
    "$PROJECT_ROOT/Scripts/create-dmg.sh" "$APP_BUNDLE" "$DMG_PATH"
    (cd "$PROJECT_ROOT/releases" && shasum -a 256 "$APP_NAME-$VERSION-arm64.dmg" > "$APP_NAME-$VERSION-arm64.dmg.sha256")
    printf 'DMG: %s\n' "$DMG_PATH"
fi
