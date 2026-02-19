#!/bin/bash
set -e

APP_NAME="QuickTray"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SOURCES="Sources/QuickTrayApp.swift Sources/ClipboardManager.swift Sources/Views/ContentView.swift"
OUT_X86="$BUILD_DIR/$APP_NAME-x86_64"
OUT_ARM="$BUILD_DIR/$APP_NAME-arm64"

echo "Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Compiling for x86_64..."
swiftc $SOURCES -o "$OUT_X86" -target x86_64-apple-macosx13.0 -sdk $(xcrun --show-sdk-path)

echo "Compiling for arm64..."
swiftc $SOURCES -o "$OUT_ARM" -target arm64-apple-macosx13.0 -sdk $(xcrun --show-sdk-path)

echo "Creating Universal Binary..."
lipo -create "$OUT_X86" "$OUT_ARM" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Clean up temp binaries
rm "$OUT_X86" "$OUT_ARM"

echo "Copying Resources..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

echo "Signing app..."
# Ad-hoc signing to ensure the bundle structure is valid
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done! App is at $APP_BUNDLE"
