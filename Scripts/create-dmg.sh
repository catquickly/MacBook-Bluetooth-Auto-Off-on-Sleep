#!/bin/bash
set -euo pipefail
[[ $# -eq 2 && -d "$1" && "$2" == /* ]] || { printf 'Usage: %s /path/App.app /absolute/path/output.dmg\n' "$0" >&2; exit 2; }
APP_BUNDLE="$1"
DMG_PATH="$2"
[[ ! -e "$DMG_PATH" ]] || { printf 'Output already exists: %s\n' "$DMG_PATH" >&2; exit 1; }
APP_NAME="Auto Turn Off Bluetooth"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-turn-off-bluetooth-dmg.XXXXXX")"
STAGING_DIR="$BUILD_DIR/dmg-root"
RW_DMG="$BUILD_DIR/installer-rw.dmg"
BUILD_VOLUME_NAME="ATOB-$(basename "$BUILD_DIR")"
DEVICE=""
cleanup() {
    if [[ -n "$DEVICE" ]]; then hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true; fi
    rm -rf -- "$BUILD_DIR"
}
trap cleanup EXIT
mkdir -p "$STAGING_DIR/.background" "$(dirname -- "$DMG_PATH")"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$BUILD_DIR/draw-background.swift" <<'SWIFT'
import AppKit
let width = 1000
let height = 620
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Could not create installer background") }
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
let arrow = NSBezierPath()
arrow.lineWidth = 9
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 425, y: 310))
arrow.line(to: NSPoint(x: 575, y: 310))
arrow.move(to: NSPoint(x: 530, y: 355))
arrow.line(to: NSPoint(x: 575, y: 310))
arrow.line(to: NSPoint(x: 530, y: 265))
NSColor(calibratedWhite: 0.30, alpha: 1).setStroke()
arrow.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode installer background") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
xcrun swiftc -framework AppKit -O -o "$BUILD_DIR/draw-background" "$BUILD_DIR/draw-background.swift"
"$BUILD_DIR/draw-background" "$STAGING_DIR/.background/background.png"
hdiutil create -volname "$BUILD_VOLUME_NAME" -srcfolder "$STAGING_DIR" -format UDRW "$RW_DMG" >/dev/null
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -nobrowse)"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// { print $1; exit }')"
[[ -n "$DEVICE" ]] || { printf 'Could not locate the installer volume.\n' >&2; exit 1; }
/usr/bin/osascript - "$BUILD_VOLUME_NAME" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            delay 2
            set installerWindow to container window
            set current view of installerWindow to icon view
            set toolbar visible of installerWindow to false
            set statusbar visible of installerWindow to false
            set bounds of installerWindow to {120, 100, 1120, 750}
            set iconOptions to icon view options of installerWindow
            set icon size of iconOptions to 256
            set text size of iconOptions to 16
            set arrangement of iconOptions to not arranged
            set background picture of iconOptions to file ".background:background.png"
            set position of item "Auto Turn Off Bluetooth.app" of installerWindow to {260, 350}
            set position of item "Applications" of installerWindow to {760, 350}
            update without registering applications
            delay 2
            close installerWindow
            delay 2
        end tell
    end tell
end run
APPLESCRIPT
sync
diskutil renameVolume "$DEVICE" "$APP_NAME" >/dev/null
hdiutil detach "$DEVICE" -quiet >/dev/null
DEVICE=""
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null
printf 'PACKAGED: %s\n' "$DMG_PATH"
