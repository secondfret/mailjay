#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MailJay"
BUNDLE_ID="com.personal.MailJay"
MIN_SYSTEM_VERSION="14.0"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SPARKLE_PUBLIC_KEY="yOLZgIwWd8gXaOx2M89AUIFLbBc6W2NYWXDCjIBb/+g="
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://mailjay.secondfret.workers.dev/appcast.xml}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="MailJay_MailJay.bundle"
APP_ICON="$ROOT_DIR/Sources/MailJay/Resources/AppIcon.icns"
ARCHIVE_PATH="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_LOAD_PATH="@rpath/Sparkle.framework/Versions/B/Sparkle"
FRAMEWORKS_RPATH="@executable_path/../Frameworks"

DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

cd "$ROOT_DIR"

print_usage() {
  cat >&2 <<USAGE
usage: $0 [run|debug|logs|telemetry|verify|sign|package|notarize]

Modes:
  run        Build, ad hoc sign, and open the app.
  verify     Build, ad hoc sign, open the app, and confirm it launched.
  sign       Build and Developer ID sign the app in dist/.
  package    Developer ID sign, verify, and create dist/$APP_NAME.zip.
  notarize   Package and submit the zip to Apple notarization.

Environment:
  DEVELOPER_ID_IDENTITY       Optional signing identity override.
  NOTARY_KEYCHAIN_PROFILE     Required for notarize mode. Create it with:
                              xcrun notarytool store-credentials <profile-name>
  VERSION / BUILD_NUMBER      Optional Info.plist version values.
USAGE
}

developer_id_identity() {
  if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
    echo "$DEVELOPER_ID_IDENTITY"
    return
  fi

  security find-identity -p codesigning -v |
    sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' |
    head -n 1
}

remove_appledouble_artifacts() {
  find "$APP_BUNDLE" \( -name '._*' -o -name '__MACOSX' \) -print -exec rm -rf {} +
}

create_zip_archive() {
  rm -f "$ARCHIVE_PATH"
  COPYFILE_DISABLE=1 /usr/bin/ditto \
    -c -k \
    --norsrc \
    --noextattr \
    --noqtn \
    --keepParent \
    "$APP_BUNDLE" \
    "$ARCHIVE_PATH"
}

embed_oauth_secrets() {
  local secrets_plist="$ROOT_DIR/Config/GoogleOAuth.plist"
  local secrets_example="$ROOT_DIR/Config/GoogleOAuth.plist.example"
  if [[ ! -f "$secrets_plist" ]]; then
    echo "error: missing $secrets_plist" >&2
    echo "Copy the example and add your Desktop OAuth client credentials:" >&2
    echo "  cp \"$secrets_example\" \"$secrets_plist\"" >&2
    exit 1
  fi
  local client_id
  client_id="$(/usr/libexec/PlistBuddy -c 'Print :ClientID' "$secrets_plist" 2>/dev/null || true)"
  local client_id_trimmed
  client_id_trimmed="$(printf '%s' "$client_id" | tr -d '[:space:]')"
  if [[ -z "$client_id_trimmed" || "$client_id_trimmed" == YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com ]]; then
    echo "error: Config/GoogleOAuth.plist has no real ClientID yet." >&2
    echo "Create a Desktop OAuth client in Google Cloud Console and paste ClientID / ClientSecret into that file." >&2
    exit 1
  fi
  cp "$secrets_plist" "$APP_RESOURCES/GoogleOAuth.plist"
}

build_app() {
  swift build -c release
  local build_binary build_dir
  build_binary="$(swift build -c release --show-bin-path)/$APP_NAME"
  build_dir="$(swift build -c release --show-bin-path)"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  while IFS= read -r rpath; do
    case "$rpath" in
      /Applications/Xcode.app/*|"$HOME"/*|"$ROOT_DIR"/*)
        install_name_tool -delete_rpath "$rpath" "$APP_BINARY"
        ;;
    esac
  done < <(otool -l "$APP_BINARY" | awk '/cmd LC_RPATH/{in_rpath=1; next} in_rpath && /path /{print $2; in_rpath=0}')

  if ! otool -l "$APP_BINARY" | grep -Fq "path $FRAMEWORKS_RPATH "; then
    install_name_tool -add_rpath "$FRAMEWORKS_RPATH" "$APP_BINARY"
  fi

  if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noqtn "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
  else
    echo "Sparkle.framework was not found at $SPARKLE_FRAMEWORK" >&2
    echo "Run swift package resolve and try again." >&2
    exit 1
  fi

  if [[ -d "$build_dir/$RESOURCE_BUNDLE_NAME" ]]; then
    cp -R "$build_dir/$RESOURCE_BUNDLE_NAME" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
  fi

  if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
  fi

  mkdir -p "$APP_RESOURCES/Onboarding"
  cp "$ROOT_DIR/Sources/MailJay/Resources/Onboarding/"*.png "$APP_RESOURCES/Onboarding/"
  embed_oauth_secrets
  remove_appledouble_artifacts

  if otool -L "$APP_BINARY" | grep -Fq "$SPARKLE_LOAD_PATH"; then
    if [[ ! -f "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/Sparkle" ]]; then
      echo "MailJay links Sparkle, but Sparkle.framework was not copied into Contents/Frameworks." >&2
      exit 1
    fi
    if ! otool -l "$APP_BINARY" | grep -Fq "path $FRAMEWORKS_RPATH "; then
      echo "MailJay links Sparkle, but the app binary is missing rpath $FRAMEWORKS_RPATH." >&2
      exit 1
    fi
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUEnableInstallerLauncherService</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
</dict>
</plist>
PLIST
}

sign_app() {
  local identity="$1"
  local runtime_args=()

  if [[ "$identity" != "-" ]]; then
    runtime_args=(--options runtime --timestamp)
  fi

  if [[ ${#runtime_args[@]} -gt 0 ]]; then
    /usr/bin/codesign --force --deep --sign "$identity" "${runtime_args[@]}" "$APP_BUNDLE"
  else
    /usr/bin/codesign --force --deep --sign "$identity" "$APP_BUNDLE"
  fi
}

verify_signature() {
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  /usr/sbin/spctl -a -vv -t exec "$APP_BUNDLE" || true
}

build_and_adhoc_sign() {
  build_app
  sign_app "-"
}

build_and_developer_id_sign() {
  build_app
  local identity
  identity="$(developer_id_identity)"
  if [[ -z "$identity" ]]; then
    echo "No Developer ID Application signing identity was found." >&2
    echo "Install one in Keychain Access or set DEVELOPER_ID_IDENTITY." >&2
    exit 1
  fi
  echo "Signing with: $identity"
  sign_app "$identity"
  verify_signature
}

package_app() {
  build_and_developer_id_sign
  create_zip_archive
  echo "Created $ARCHIVE_PATH"
}

create_and_notarize_dmg() {
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate -v "$DMG_PATH"
  echo "Created notarized $DMG_PATH"
}

notarize_app() {
  if [[ -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    echo "NOTARY_KEYCHAIN_PROFILE is required for notarize mode." >&2
    echo "Create one with: xcrun notarytool store-credentials <profile-name>" >&2
    exit 1
  fi

  package_app
  xcrun notarytool submit "$ARCHIVE_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  remove_appledouble_artifacts
  create_zip_archive
  create_and_notarize_dmg
  echo "Created notarized $ARCHIVE_PATH"
  verify_signature
  xcrun stapler validate -v "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_and_adhoc_sign
    open_app
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_and_adhoc_sign
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_and_adhoc_sign
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_and_adhoc_sign
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_and_adhoc_sign
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  sign)
    build_and_developer_id_sign
    ;;
  package)
    package_app
    ;;
  notarize)
    notarize_app
    ;;
  --help|-h|help)
    print_usage
    ;;
  *)
    print_usage
    exit 2
    ;;
esac
