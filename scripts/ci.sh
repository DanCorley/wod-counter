#!/usr/bin/env bash
set -euo pipefail

# Generate the Xcode project from Project.yml, then build and test the app.
# Requires Xcode 16+ (the test target uses Swift Testing alongside XCTest).
#
# Prerequisite: xcodegen (https://github.com/yonaskolb/XcodeGen)
#   brew install xcodegen
# Override the binary location with XCODEGEN=/path/to/xcodegen.
#
# Destinations can be overridden. The simulator name depends on the installed
# runtime (Xcode 17/18 use "iPhone 16"; newer runtimes may only have
# "iPhone 18 Pro"), so set TEST_DESTINATION when the default is unavailable:
#   BUILD_DESTINATION='generic/platform=iOS' ./scripts/ci.sh
#   TEST_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro' ./scripts/ci.sh

cd "$(dirname "$0")/.."

XCODEGEN="${XCODEGEN:-xcodegen}"
BUILD_DESTINATION="${BUILD_DESTINATION:-generic/platform=iOS}"
TEST_DESTINATION="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16}"

if ! command -v "$XCODEGEN" >/dev/null 2>&1; then
  echo "error: '$XCODEGEN' not found. Install XcodeGen (brew install xcodegen) or set XCODEGEN=/path/to/xcodegen." >&2
  exit 1
fi

echo "==> Generating WODCounter.xcodeproj"
"$XCODEGEN" generate --spec Project.yml

echo "==> Building for $BUILD_DESTINATION"
xcodebuild \
  -project WODCounter.xcodeproj \
  -scheme WODCounter \
  -destination "$BUILD_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Testing on $TEST_DESTINATION"
xcodebuild \
  -project WODCounter.xcodeproj \
  -scheme WODCounter \
  -destination "$TEST_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  test
