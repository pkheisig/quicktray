#!/bin/bash
set -e

APP_NAME="QuickTray"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SOURCES=$(find Sources -name '*.swift' | sort)
OUT_ARM="$BUILD_DIR/$APP_NAME"

echo "Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Compiling for arm64..."
swiftc $SOURCES -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" -target arm64-apple-macosx13.0 -sdk $(xcrun --show-sdk-path)

echo "Copying Resources..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

echo "Signing app..."
# Try to find a valid developer identity to avoid macOS resetting Accessibility permissions on every build.
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$IDENTITY" ]; then
    # Fallback to ad-hoc signing
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "Notice: Used ad-hoc signing. macOS may prompt for permissions again."
else
    echo "Found developer identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
fi

echo "Done! App is at $APP_BUNDLE"
