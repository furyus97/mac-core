#!/bin/zsh
set -euo pipefail

# Creates a locally signed Universal evaluation build. NOT a public release:
# no Developer ID certificate, notarization, or Gatekeeper acceptance is implied.
SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacCore-local.XXXXXX")"
OUTPUT_DIR="$PROJECT_ROOT/build/releases/local"
STAMP="$(date +%Y%m%d-%H%M%S)"

xcodebuild -project "$PROJECT_ROOT/MacCoreCleaner.xcodeproj" \
  -scheme MacCoreCleaner -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build

APP_PATH="$WORK_DIR/DerivedData/Build/Products/Release/MacCoreCleaner.app"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/MacCoreCleaner")"
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]]
codesign --force --sign - --options runtime "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
mkdir -p "$OUTPUT_DIR"
FINAL_ZIP="$OUTPUT_DIR/MacCore-$VERSION-local-$STAMP.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"
print "LOCAL_EVALUATION_ZIP=$FINAL_ZIP"
print "LOCAL_EVALUATION_APP=$APP_PATH"
print "This build is not notarized and must not be advertised as a public release."
