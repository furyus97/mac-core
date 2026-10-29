#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
PROJECT_PATH="$PROJECT_ROOT/MacCoreCleaner.xcodeproj"
SCHEME="MacCoreCleaner"

if [[ -z "${MAC_CORE_DEVELOPMENT_TEAM:-}" ]]; then
  print -u2 "MAC_CORE_DEVELOPMENT_TEAM is required. Set it to your Apple Developer Team ID."
  exit 64
fi

if [[ -z "${MAC_CORE_NOTARY_PROFILE:-}" ]]; then
  print -u2 "MAC_CORE_NOTARY_PROFILE is required. Public releases must be notarized."
  exit 64
fi

SIGNING_IDENTITY="${MAC_CORE_SIGNING_IDENTITY:-Developer ID Application}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$PROJECT_ROOT/build/releases/$STAMP"
# Build outside Desktop/iCloud/File Provider roots so Finder metadata cannot
# invalidate code signatures. Keep the working directory for diagnostics.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacCore-release.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
ARCHIVE_PATH="$WORK_DIR/MacCore.xcarchive"

mkdir -p "$OUTPUT_DIR"

print "Running safety regression tests…"
xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA/tests" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES

print "Creating signed Universal release archive…"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA/archive" \
  DEVELOPMENT_TEAM="$MAC_CORE_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_PATH="$ARCHIVE_PATH/Products/Applications/MacCoreCleaner.app"
if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Archive did not contain the expected app: $APP_PATH"
  exit 66
fi

print "Verifying Developer ID signature…"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/MacCoreCleaner")"
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]]
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE_INFO" != *"Authority=Developer ID Application:"* ]]; then
  print -u2 "A Developer ID Application signature is required for direct distribution."
  exit 65
fi

SUBMISSION_ZIP="$WORK_DIR/MacCore-notary-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

print "Submitting to Apple notary service…"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$MAC_CORE_NOTARY_PROFILE" \
  --wait

print "Stapling and validating notarization ticket…"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

FINAL_ZIP="$OUTPUT_DIR/MacCore-$STAMP.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"

print "Release artifact: $FINAL_ZIP"
print "Build archive and diagnostics: $WORK_DIR"
