#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Chrome Profile Router.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -framework AppKit -framework SwiftUI Sources/RouterCore.swift Sources/URLRules.swift Sources/main.swift -o "$APP/Contents/MacOS/ChromeProfileRouter"
python3 scripts/package.py "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"
