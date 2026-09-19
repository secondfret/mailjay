# Signing MailJay

The build script handles the usual local and distribution signing steps.

## Local development

```sh
./script/build_and_run.sh run
```

This builds `dist/MailJay.app`, signs it ad hoc, and opens it. Ad hoc signing is enough for local development.

## Signed zip for distribution

```sh
./script/build_and_run.sh package
```

This uses the first `Developer ID Application` certificate in your keychain, verifies the signature, and creates:

```text
dist/MailJay.zip
```

To force a specific identity:

```sh
DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/build_and_run.sh package
```

## Notarization

Reuse the existing notarytool keychain profile:

```sh
NOTARY_KEYCHAIN_PROFILE=AgentScanNotary ./script/build_and_run.sh notarize
```

Or create a dedicated profile:

```sh
xcrun notarytool store-credentials MailJayNotary
```

Gatekeeper will reject a Developer ID app until notarization succeeds. A `spctl` result of `Unnotarized Developer ID` means the certificate signing worked and the app still needs the Apple notarization step.

Always validate the stapled app before distribution:

```sh
xcrun stapler validate -v dist/MailJay.app
spctl -a -vv -t open --context context:primary-signature dist/MailJay.app
```

Expected: stapler says the validate action worked, and `spctl` reports `accepted` with `source=Notarized Developer ID`.

## Sparkle and Cloudflare release

MailJay is configured with:

```text
SUFeedURL=https://mailjay.secondfret.workers.dev/appcast.xml
SUPublicEDKey=yOLZgIwWd8gXaOx2M89AUIFLbBc6W2NYWXDCjIBb/+g=
```

The private Sparkle update key is stored in the macOS login keychain under the `MailJay` account.

Prepare a notarized public release:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 NOTARY_KEYCHAIN_PROFILE=AgentScanNotary ./script/prepare_release.sh
./script/deploy_cloudflare.sh
```

The public download page is:

```text
https://mailjay.secondfret.workers.dev
```

The marketing page (not linked from the homepage yet) is:

```text
https://secondfret.net/mailjay/
```
