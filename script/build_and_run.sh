#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MailJay"
BUNDLE_ID="com.personal.MailJay"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Sources/MailJay/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
mkdir -p "$APP_RESOURCES/Onboarding"
cp "$ROOT_DIR/Sources/MailJay/Resources/Onboarding/"*.png "$APP_RESOURCES/Onboarding/"
echo "Embedded onboarding images."

SECRETS_PLIST="$ROOT_DIR/Config/GoogleOAuth.plist"
SECRETS_EXAMPLE="$ROOT_DIR/Config/GoogleOAuth.plist.example"
if [[ ! -f "$SECRETS_PLIST" ]]; then
  echo "error: missing $SECRETS_PLIST" >&2
  echo "Copy the example and add your Desktop OAuth client credentials:" >&2
  echo "  cp \"$SECRETS_EXAMPLE\" \"$SECRETS_PLIST\"" >&2
  exit 1
fi
CLIENT_ID="$(/usr/libexec/PlistBuddy -c 'Print :ClientID' "$SECRETS_PLIST" 2>/dev/null || true)"
CLIENT_ID_TRIMMED="$(printf '%s' "$CLIENT_ID" | tr -d '[:space:]')"
if [[ -z "$CLIENT_ID_TRIMMED" || "$CLIENT_ID_TRIMMED" == YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com ]]; then
  echo "error: Config/GoogleOAuth.plist has no real ClientID yet." >&2
  echo "Create a Desktop OAuth client in Google Cloud Console and paste ClientID / ClientSecret into that file." >&2
  exit 1
fi
cp "$SECRETS_PLIST" "$APP_RESOURCES/GoogleOAuth.plist"
echo "Embedded Google OAuth client credentials."

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>MailJay</string>
  <key>CFBundleDisplayName</key>
  <string>MailJay</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Stable signing keeps Keychain access quiet across rebuilds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1 || true)"
fi
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1 || true)"
fi
if [[ -n "${CODESIGN_IDENTITY}" ]]; then
  echo "Signing with ${CODESIGN_IDENTITY}..."
  codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
else
  echo "warning: no Developer ID / Apple Development identity found; Keychain may prompt on each rebuild" >&2
  codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
