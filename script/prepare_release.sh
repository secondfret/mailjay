#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MailJay"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$ROOT_DIR/site/public"
DOWNLOADS_DIR="$SITE_DIR/downloads"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://mailjay.secondfret.workers.dev}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-MailJay}"
APP_ICON_SRC="$ROOT_DIR/Sources/MailJay/Resources/AppIcon.icns"

cd "$ROOT_DIR"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  swift package resolve
fi

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" NOTARY_KEYCHAIN_PROFILE="$NOTARY_KEYCHAIN_PROFILE" ./script/build_and_run.sh notarize
else
  VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./script/build_and_run.sh package
fi

mkdir -p "$DOWNLOADS_DIR"

# generate_appcast fails on duplicate archives (latest + versioned, or dmg + zip).
tmp_latest_zip="$(mktemp -t MailJay-latest.zip.XXXXXX)"
tmp_dmgs="$(mktemp -d -t MailJay-dmgs.XXXXXX)"
cp "$DOWNLOADS_DIR/$APP_NAME-latest.zip" "$tmp_latest_zip" 2>/dev/null || true
rm -f "$DOWNLOADS_DIR/$APP_NAME-latest.zip"
shopt -s nullglob
for dmg in "$DOWNLOADS_DIR"/*.dmg; do
  mv "$dmg" "$tmp_dmgs/"
done
shopt -u nullglob

if [[ -f "$APP_ICON_SRC" ]]; then
  sips -s format png "$APP_ICON_SRC" --out /tmp/mailjay-app-icon-full.png >/dev/null
  sips -z 512 512 /tmp/mailjay-app-icon-full.png --out "$SITE_DIR/app-icon.png" >/dev/null
fi

cp "$ROOT_DIR/dist/$APP_NAME.zip" "$DOWNLOADS_DIR/$APP_NAME-$VERSION.zip"

# Keep worker.js latestVersion in sync with this release.
if [[ -f "$ROOT_DIR/cloudflare/worker.js" ]]; then
  sed -i '' "s/const latestVersion = \".*\";/const latestVersion = \"$VERSION\";/" "$ROOT_DIR/cloudflare/worker.js"
fi

cat >"$DOWNLOADS_DIR/$APP_NAME-$VERSION.html" <<HTML
<!doctype html>
<html>
  <body>
    <h1>MailJay $VERSION</h1>
    <p>Signed Developer ID release for macOS.</p>
    <ul>
      <li>Inbox triage with Gmail + Jev</li>
      <li>Review every proposed archive or trash action</li>
      <li>Sparkle auto-updates enabled</li>
    </ul>
  </body>
</html>
HTML

# Appcast must be generated from versioned zips only — never while matching
# DMGs or *-latest.zip aliases are present (Sparkle treats them as duplicates).
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$PUBLIC_BASE_URL/downloads/" \
  --release-notes-url-prefix "$PUBLIC_BASE_URL/downloads/" \
  --link "$PUBLIC_BASE_URL/" \
  --maximum-versions 5 \
  -o "$SITE_DIR/appcast.xml" \
  "$DOWNLOADS_DIR"

cp "$ROOT_DIR/dist/$APP_NAME.zip" "$DOWNLOADS_DIR/$APP_NAME-latest.zip"
if [[ -f "$ROOT_DIR/dist/$APP_NAME.dmg" ]]; then
  cp "$ROOT_DIR/dist/$APP_NAME.dmg" "$DOWNLOADS_DIR/$APP_NAME-$VERSION.dmg"
  cp "$ROOT_DIR/dist/$APP_NAME.dmg" "$DOWNLOADS_DIR/$APP_NAME-latest.dmg"
fi

# Restore any older DMGs that were temporarily moved aside.
shopt -s nullglob
for dmg in "$tmp_dmgs"/*.dmg; do
  base="$(basename "$dmg")"
  if [[ ! -f "$DOWNLOADS_DIR/$base" ]]; then
    mv "$dmg" "$DOWNLOADS_DIR/"
  fi
done
shopt -u nullglob
rm -rf "$tmp_dmgs"
rm -f "$tmp_latest_zip"

echo "Prepared $SITE_DIR"
echo "Download: $PUBLIC_BASE_URL/download"
echo "Appcast:  $PUBLIC_BASE_URL/appcast.xml"
