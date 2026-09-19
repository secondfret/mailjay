# MailJay

A personal macOS inbox triage app powered by Google's Gmail API and TypeSafe's Jev model.

The app downloads a configurable batch of recent inbox messages (default 300), asks Jev to label each one, and presents every proposed action for review. It never permanently deletes mail: delete moves messages to Gmail Trash. Archive removes Inbox (and may apply a `Jev/…` label).

## Requirements

- macOS 14 or newer
- A Google Cloud project with the Gmail API enabled
- A Google OAuth 2.0 client created with application type **Desktop app** (developer embeds this; end users never see it)
- A TypeSafe Jev API key

## Google setup (developer)

1. In Google Cloud Console, create or select a project.
2. Enable **Gmail API**.
3. Configure the OAuth consent screen. For a personal test, add your Gmail address as a test user.
4. Create an OAuth client with application type **Desktop app**.
5. Embed the client credentials locally (gitignored):

```sh
cp Config/GoogleOAuth.plist.example Config/GoogleOAuth.plist
# Edit Config/GoogleOAuth.plist — set ClientID and ClientSecret
```

`./script/build_and_run.sh` copies that plist into `MailJay.app`. End users only click **Connect Gmail**; they never enter a client ID or secret.

Desktop OAuth client secrets are not confidential (Google’s model for installed apps). Keep `Config/GoogleOAuth.plist` out of git; do not treat the embedded values as a server-side secret.

Google redirects to a temporary `127.0.0.1` port during sign-in. This is the standard loopback flow for an installed desktop app; the listener stops immediately after authorization.

## Classifier setup

In **Settings**, paste your TypeSafe Jev API key and optionally adjust **Messages per batch** and confidence threshold.

## Run

```sh
./script/build_and_run.sh
```

Or build/test without launching:

```sh
swift build
swift test
```

## Release (signing / Sparkle / Cloudflare)

Follow `AGENTS.md` and `SIGNING.md`. Short path:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 NOTARY_KEYCHAIN_PROFILE=AgentScanNotary ./script/prepare_release.sh
./script/deploy_cloudflare.sh
```

Public URLs:

- Download worker: https://mailjay.secondfret.workers.dev/
- Direct download: https://mailjay.secondfret.workers.dev/download
- Marketing page: https://secondfret.net/mailjay/ (not linked from homepage yet)
- Sparkle appcast: https://mailjay.secondfret.workers.dev/appcast.xml
