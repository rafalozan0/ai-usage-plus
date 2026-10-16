# Releasing AI Usage Plus

AI Usage Plus ships as a universal DMG, installs through the
`rafalozan0/homebrew-tap` cask, and uses Sparkle 2 for signed over-the-air
updates. Releases are built by GitHub Actions when a `v*` tag is pushed.

## Signing model

There is no paid Apple Developer account, so builds are not notarized.

- **Code signing:** a self-signed certificate
  (`AI Usage Plus Code Signing (rafalozan0)`, valid until 2036). Every release
  uses the same certificate, so the app's designated requirement stays the same
  and Keychain **Always Allow** grants survive updates. Hardened Runtime is off
  because, without a Team ID, library validation would reject Sparkle.
- **Updates:** Sparkle EdDSA key. The public key is in `AIUsage/Info.plist`;
  the private key is in the `ai-usage-plus` login Keychain entry and in GitHub
  Secrets.
- **Gatekeeper:** the Homebrew cask clears the quarantine flag after
  installing. DMG users follow the **Open Anyway** steps in the README.

## Secrets

| Secret | Contents |
|---|---|
| `SIGNING_CERT_P12_BASE64` | Base64 of the signing certificate `.p12` |
| `SIGNING_CERT_PASSWORD` | Password of the `.p12` |
| `SPARKLE_ED_PRIVATE_KEY` | Output of `generate_keys --account ai-usage-plus -x` |
| `TAP_GITHUB_TOKEN` | Fine-grained token with Contents read/write on `rafalozan0/homebrew-tap` |

Back up the `.p12`, its password, and the Sparkle private key outside GitHub.
Losing the certificate makes every user re-approve Keychain access. Losing the
Sparkle key stops installed copies from updating themselves.

## Prepare a version

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in the
   Xcode project.
2. Add `docs/releases/<version>.md`.
3. Commit, run the tests, and push to `main`.

## Publish

```bash
version=1.0.1
git tag -a "v$version" -m "AI Usage Plus $version"
git push origin "v$version"
```

The `Release` workflow then:

- checks that the tag is on `main`;
- runs the test suite;
- runs `scripts/package_release.sh`, which builds the universal app, re-signs
  Sparkle and the app with the self-signed certificate, runs a launch smoke
  test, and creates `dist/v<version>/AI-Usage-Plus.dmg` plus the signed
  appcast;
- creates the GitHub release with the DMG and its SHA-256;
- commits `appcast.xml` to `main`, after the DMG is live;
- updates `version` and `sha256` in `Casks/ai-usage-plus.rb` in the tap.

Afterwards, check that the raw appcast and the DMG URL both return HTTP 200.

## Build locally

With the Sparkle key in the login Keychain and the certificate imported:

```bash
AI_USAGE_CODESIGN_IDENTITY="AI Usage Plus Code Signing (rafalozan0)" \
  ./scripts/package_release.sh "$version"
```

`AI_USAGE_CODESIGN_KEYCHAIN` selects a non-default keychain, and
`SPARKLE_ED_KEY_FILE` reads the Sparkle key from a file instead of the
Keychain. With no identity, the script falls back to a Developer ID
certificate if one exists (and can notarize with `NOTARYTOOL_PROFILE`), or to
an ad-hoc build.

Local runs rewrite `appcast.xml`. Don't commit it; CI owns the feed.
