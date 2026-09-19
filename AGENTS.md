# Agent Instructions

This repo is a SwiftPM macOS app distributed from Cloudflare Workers static assets.

When Josh asks to update, release, sign, notarize, or distribute MailJay, read this file first and follow it exactly. The public app must be Developer ID signed, notarized, stapled, packaged as a notarized DMG for direct downloads, have a Sparkle appcast generated from the versioned zip archive, and then deployed to Cloudflare.

## Project Shape

- App product: `MailJay`
- Bundle ID: `com.personal.MailJay`
- Minimum macOS: `14.0`
- Public site: `https://mailjay.secondfret.workers.dev`
- Marketing page (direct URL only): `https://secondfret.net/mailjay/`
- Appcast: `https://mailjay.secondfret.workers.dev/appcast.xml`
- Main release scripts:
  - `script/build_and_run.sh`
  - `script/prepare_release.sh`
  - `script/deploy_cloudflare.sh`
- Notary profile currently used in this repo: `AgentScanNotary`
- Developer ID identity currently used by auto-detection: `Developer ID Application: Joshua Johnson (2FUHTM754M)`
- Sparkle keychain account: `MailJay`
- Sparkle public key: `yOLZgIwWd8gXaOx2M89AUIFLbBc6W2NYWXDCjIBb/+g=`

## Local Build And Run

Use:

```sh
./script/build_and_run.sh verify
```

This builds `dist/MailJay.app`, ad hoc signs it, opens it, and verifies the process launches.

## Public Release Command

For a public download, do not use `package` alone. Use notarization:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 NOTARY_KEYCHAIN_PROFILE=AgentScanNotary ./script/prepare_release.sh
./script/deploy_cloudflare.sh
```

That flow must:

1. Build `dist/MailJay.app`.
2. Developer ID sign it with hardened runtime.
3. Zip it as `dist/MailJay.zip`.
4. Submit the zip to Apple notarization.
5. Wait for `status: Accepted`.
6. Staple the ticket to `dist/MailJay.app`.
7. Recreate `dist/MailJay.zip` from the stapled app.
8. Create, notarize, and staple `dist/MailJay.dmg`.
9. Copy versioned zip/dmg into `site/public/downloads`, regenerate appcast, deploy.

If `xcrun stapler validate -v dist/MailJay.app` does not pass, do not deploy.

The zip must not contain AppleDouble metadata files. Create release zips with:

```sh
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --keepParent dist/MailJay.app dist/MailJay.zip
```

Always verify:

```sh
zipinfo -1 dist/MailJay.zip | rg '(^|/)(\\._|__MACOSX)' && exit 1 || true
```

## Sparkle Appcast Notes

Do not run `generate_appcast` while both `MailJay-latest.zip` and the matching versioned zip are in `site/public/downloads`. Temporarily remove latest aliases and DMGs before appcast generation. `prepare_release.sh` already does this.

## Required Verification Before Saying It Is Fixed

Download the exact public artifacts and verify them:

```sh
VERSION=0.1.0
rm -rf /tmp/mailjay-check
mkdir -p /tmp/mailjay-check
curl -fsSL https://mailjay.secondfret.workers.dev/downloads/MailJay-$VERSION.zip \
  -o /tmp/mailjay-check/MailJay-$VERSION.zip
ditto -x -k /tmp/mailjay-check/MailJay-$VERSION.zip /tmp/mailjay-check
xcrun stapler validate -v /tmp/mailjay-check/MailJay.app
spctl -a -vv -t open --context context:primary-signature /tmp/mailjay-check/MailJay.app

curl -fsSL https://mailjay.secondfret.workers.dev/downloads/MailJay-latest.dmg \
  -o /tmp/mailjay-check/MailJay-latest.dmg
xcrun stapler validate -v /tmp/mailjay-check/MailJay-latest.dmg
```

Expected results:

- `xcrun stapler validate` says `The validate action worked!`
- `spctl` says `accepted`
- `spctl` source is `Notarized Developer ID`
- `/download` serves `MailJay-latest.dmg`

Also verify Sparkle is bundled:

```sh
otool -l dist/MailJay.app/Contents/MacOS/MailJay | sed -n '/LC_RPATH/,+3p'
test -f dist/MailJay.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle
```

Expected rpath:

```text
@executable_path/../Frameworks
```

Do not ship machine-local rpaths. Do not sign with an entitlements file unless a real entitlement is needed.

## Current Architecture Note

The current release is `arm64` only and the appcast advertises `sparkle:hardwareRequirements` as `arm64`. Do not claim Intel support unless the release process is changed to build and verify a universal binary.

Google OAuth Desktop credentials are embedded from gitignored `Config/GoogleOAuth.plist` at package time. End users never enter a client ID/secret.
