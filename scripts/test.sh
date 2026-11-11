#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 Sources/RouterCore.swift Tests/main.swift -o build/core-tests
build/core-tests
python3 Tests/native_host.py
node --check extension/background.js
node --check extension/popup.js
