#!/bin/bash
set -e

APP_NAME="QuickTray"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - Info.plist)
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SOURCES=$(find Sources -name '*.swift' | sort)
OUT_ARM="$BUILD_DIR/$APP_NAME"

RUNNING_APP="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
RUNNING_PIDS=$(pgrep -f "$RUNNING_APP" || true)
if [ -n "$RUNNING_PIDS" ]; then
    echo "Stopping running $APP_NAME..."
    for PID in $RUNNING_PIDS; do
        kill "$PID" 2>/dev/null || true
    done
    sleep 1
fi

echo "Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Compiling optimized arm64 build..."
swiftc $SOURCES \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -O \
    -whole-module-optimization

echo "Copying Resources..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

echo "Signing app..."
# Prefer a stable developer identity when one is available.
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$IDENTITY" ]; then
    # Fallback to ad-hoc signing
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "Notice: Used ad-hoc signing. macOS may prompt for permissions again."
else
    echo "Found developer identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
fi

echo "Copying to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" /Applications/

echo "Resetting macOS privacy permissions for $APP_NAME..."
tccutil reset All "$BUNDLE_ID"

echo "Done! App is at $APP_BUNDLE and copied to /Applications"
