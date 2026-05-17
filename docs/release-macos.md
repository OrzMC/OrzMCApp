# macOS Release Flow

This project distributes the full macOS launcher outside the Mac App Store with
Developer ID signing, Apple notarization, and Sparkle updates.

## Prerequisites

- A `Developer ID Application` certificate installed in Keychain.
- An Apple notarytool keychain profile.
- The Sparkle EdDSA private key in Keychain, or a private key file.
- Optional: GitHub CLI authenticated for release uploads.

Create the notarytool profile once:

```bash
xcrun notarytool store-credentials "orzmc-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "2N62934Y28" \
  --password "APP_SPECIFIC_PASSWORD"
```

## One Command Release

```bash
NOTARY_KEYCHAIN_PROFILE=orzmc-notary \
./scripts/release-macos.sh
```

The script reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from
`OrzMC/Configuration/Config.xcconfig`, then creates:

- `dist/macos/<version>-<build>/...zip` for Sparkle updates
- `dist/macos/<version>-<build>/...dmg` for direct downloads
- `products/appcast.xml` updated for Sparkle

## Common Options

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
APPLE_TEAM_ID=TEAMID
NOTARY_KEYCHAIN_PROFILE=orzmc-notary
SPARKLE_ED_KEY_FILE=/path/to/sparkle_private_key
RELEASE_NOTES_FILE=/path/to/release-notes.md
PUBLISH_GITHUB=1
```

For local packaging without notarization:

```bash
SKIP_NOTARIZE=1 ./scripts/release-macos.sh
```

`SKIP_NOTARIZE=1` is only for local validation. Public downloads should be
notarized and stapled.

## GitHub Release Upload

By default the script only prepares local artifacts and updates the appcast.
To upload artifacts:

```bash
PUBLISH_GITHUB=1 \
NOTARY_KEYCHAIN_PROFILE=orzmc-notary \
./scripts/release-macos.sh
```

The default repository is `OrzGeeker/OrzMCApp`, and the default release tag is
the marketing version, matching the existing appcast URLs.

## Feed Hosting

The app currently reads:

```text
https://raw.githubusercontent.com/OrzGeeker/OrzMCApp/main/products/appcast.xml
```

That works, but a GitHub Pages or CDN URL is easier to treat as release
infrastructure. If the feed URL changes, update `SUFeedURL` in
`OrzMC/Common/Info.plist` and keep the old feed reachable until most users have
updated.

## Validation

The release script runs:

```bash
codesign --verify --deep --strict
xcrun stapler validate
spctl --assess --type execute
```

If a public build fails any of these checks, do not publish it.
