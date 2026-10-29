#!/bin/zsh
set -eu
cd "${0:A:h}"
DEST="${1:-$PWD/build/ScratchGuard.app}"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 Detector.swift main.swift -o "$DEST/Contents/MacOS/ScratchGuard" -framework AppKit -framework SwiftUI -framework AVFoundation -framework Vision -framework ServiceManagement
cp -R Sounds "$DEST/Contents/Resources/"
cp Info.plist "$DEST/Contents/Info.plist"
codesign --force --sign - --entitlements entitlements.plist "$DEST"
