#!/usr/bin/env bash
#
# Builds Yap from source and installs it into /Applications.
#
# For local development. If a Developer ID Application certificate is in your
# keychain, the build is signed with it, so macOS keeps the permissions you grant
# across rebuilds. Without one it stays ad-hoc signed, and macOS treats every
# rebuild as a new application and forgets them; Yap has a "Reset and re-grant"
# button in Settings for that. Neither is notarized: release.sh does that.

set -euo pipefail

APP_NAME="Yap2Talk"
PROJECT_NAME="Yap"
BUILD_DIR="build"
INSTALL_DIR="/Applications"
CONFIGURATION="${CONFIGURATION:-Release}"

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31mError:\033[0m %s\n" "$1" >&2; exit 1; }

# Prerequisites
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is required. Install it from the App Store, then run: xcode-select --install"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "Installing XcodeGen"
    brew install xcodegen
  else
    fail "XcodeGen is required. Install Homebrew from https://brew.sh, then run: brew install xcodegen"
  fi
fi

info "Generating Xcode project"
xcodegen generate

BUILT_APP="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
# The build's own output is filtered, so a failed build would otherwise leave the
# previous app in place to be installed as if it were new.
rm -rf "$BUILT_APP"

info "Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build \
  | grep -E "error:|warning:|BUILD" || true

[ -d "$BUILT_APP" ] || fail "Build did not produce $BUILT_APP"

IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)
if [ -n "$IDENTITY" ]; then
  info "Signing as: $IDENTITY"
  while IFS= read -r nested; do
    codesign --force --options runtime --sign "$IDENTITY" "$nested"
  done < <(find "$BUILT_APP/Contents" \( -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" \))
  codesign --force --options runtime \
    --entitlements Sources/Yap.entitlements \
    --sign "$IDENTITY" "$BUILT_APP"
  codesign --verify --strict "$BUILT_APP"
else
  info "No Developer ID Application certificate; keeping the ad-hoc signature"
fi

if pgrep -f "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
  info "Quitting the running copy"
  killall "$APP_NAME" 2>/dev/null || true
  sleep 1
fi

info "Installing to $INSTALL_DIR/$APP_NAME.app"
rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
cp -R "$BUILT_APP" "$INSTALL_DIR/"

info "Launching"
open "$INSTALL_DIR/$APP_NAME.app"

cat <<EOF

$APP_NAME is installed and running. Look for the microphone in your menu bar.

Grant the four permissions it asks for, then press the shortcut and start talking.
The default is Cmd+Shift+D, and you can change it in Settings.
EOF
