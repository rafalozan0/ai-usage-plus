# Contributing

Thanks for helping make AI Usage Plus better.

## Before you start

- Keep the app focused on lightweight, read-only quota visibility for
  supported coding agents.
- Prefer native macOS APIs and semantic system colors.
- Avoid telemetry, background log scanning, local servers, and persistent
  usage history.
- Never include credentials, tokens, or real authentication fixtures.

For a larger change, open an issue first so the scope can be agreed before
implementation.

## Development

Requirements:

- macOS 26 or newer
- Xcode 27 or newer

Run the app from the `AIUsage` scheme. Before opening a pull request, run:

```bash
xcodebuild test \
  -project AIUsage.xcodeproj \
  -scheme AIUsage \
  -destination 'platform=macOS'
```

## Translations

AI Usage Plus is available in English and Spanish. All user-facing text lives
in one String Catalog, `AIUsage/Localizable.xcstrings`. English is the source
language, so the English text in the code is the key for every translation.
The app follows the language order in **System Settings → General → Language
& Region** and falls back to English for languages it doesn't ship.

### Add a language

1. Open `AIUsage.xcodeproj` in Xcode and select `Localizable.xcstrings`.
2. Click **+** at the bottom of the language list and choose the language.
   Xcode adds it to the catalog and to the project's known regions.
3. Translate every string. Keep placeholders such as `%@` and `%lld`. If your
   language needs them in a different order, number them, for example
   `%2$@ … %1$@`. Keep command names in backticks, such as `` `claude` ``,
   exactly as written.
4. Add the language code to `CFBundleLocalizations` in `AIUsage/Info.plist`.
   Without it, macOS doesn't offer the translation.
5. Check the panel and Settings in the new language. Labels must fit the
   compact layout. Prefer shorter wording over truncated text. To launch only
   the app in another language, add `-AppleLanguages (fr)` under **Arguments
   Passed On Launch** in the scheme's Run options, using your language code.
6. Run the test suite. `LocalizationTests` fails if a declared language is
   missing a translation, or if `Info.plist` and the catalog disagree.

Strings marked **Don't Translate** in the catalog are brand names, such as
Claude Code or Codex, and symbols. The one-letter menu bar abbreviations (`S`,
`W`, `M`, and so on) are not localized, so the menu bar stays compact.

### Add or change text in the code

- SwiftUI views localize string literals automatically, for example
  `Text("Weekly")` or `.help("Refresh now")`.
- Text built as a `String` must use `String(localized:)`, for example
  `String(localized: "Reset \(minutes)m")`. Interpolated values become
  placeholders in the catalog.
- `ProviderFailure` messages are localized automatically. Pass a single
  string literal and don't build the message with `+`, or it can't be
  extracted.
- Building in Xcode adds new strings to the catalog. Add their translation for
  every shipped language before opening a pull request. Tests always run in
  English, so test assertions can use the English text.

## Pull requests

- Keep each pull request narrow.
- Explain the user-facing impact and the reason for the change.
- Add tests for provider parsing, credential handling, store behavior, or
  layout regressions when applicable.
- Include a screenshot for visible UI changes.
- Confirm that no secrets or user-specific paths are included.
