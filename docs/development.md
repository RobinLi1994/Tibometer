# Development

## Build and run

Swift package for macOS 14 or later, built with SwiftUI and AppKit.

```bash
./scripts/test.sh
./scripts/build-app.sh
open dist/Tibometer.app --args --demo --show
```

Demo mode uses synthetic data. Signing and packaging are covered in [Releasing](releasing.md).

## Source layout

| Path | Responsibility |
| --- | --- |
| `Sources/TibometerCore` | Quota models, reset detection, read-only transport, localization, webhook delivery |
| `Sources/Tibometer` | Menu bar, panel, settings, notifications, and state persistence |
| `Sources/TibometerProbe` | Command-line diagnostics |
| `Tests/TibometerCoreTests` | Core checks and fixture transport tests |
| `scripts` | Build, install, icon generation, and loopback verification |

## Codex requests

Every outgoing App Server message passes the allowlist in `CodexReadOnlyPolicy.swift`:

| Request | Parameters or purpose |
| --- | --- |
| `initialize`, `initialized` | Session handshake |
| `account/read` | `refreshToken: false` |
| `account/rateLimits/read` | Account quota and credit data |
| `thread/list` | `useStateDbOnly: true` |
| `account/usage/read` | Usage for an existing task |

Codex discovery uses the application identifier `com.openai.codex` and its bundled `Contents/Resources/codex` executable. Connection results apply only to the source configuration that started the request.

## Quota and reset rules

- `usedPercent` is converted to remaining percentage. Values are clamped to 0–100; unavailable or non-finite values stay unavailable.
- Window duration identifies 5H (300 minutes) and 7D (10080 minutes), regardless of whether the server returns them in `primary` or `secondary`.
- `rateLimitsByLimitId` is authoritative when present. Only the main `codex` bucket is displayed or monitored.
- Percentage labels round down; a positive value below 1% displays `<1%`. Only a completely unused window displays 100%.
- The first sample establishes a baseline. A return to zero usage or a confirmed new window after the previous deadline creates a reset event. A deadline alone does not prove a reset.
- Account changes establish a new baseline. Missing samples preserve the previous baseline. Stored event identifiers prevent repeated alerts after restarting.
- Reset notifications always use the 100% reset message. Snapshot values, history fields, and webhook quota fields retain the observed remaining quota.

The local notification claim is persisted before submission, preventing duplicate banners after a restart. A crash between the claim and submission can lose a banner; the reset remains in history. Webhook retries use the same event ID; receivers should deduplicate it.

## Local storage

The app's preference domain is `app.tibometer.codex-limits`. Menu bar placement uses the autosave name `Tibometer.QuotaStatus`.

- `~/Library/Application Support/Tibometer/state.json`: last snapshot, detector baseline, and the latest 100 reset records.
- `~/Library/Application Support/Tibometer/webhook.json`: URL, bearer token, and signing secret; directory permissions are `0700`, file permissions are `0600`.
- UserDefaults: language, menu bar style, selected limits, and application settings.

Codex manages authentication. Account identifiers are hashed before storage and omitted from webhook payloads.

## Diagnostics

```bash
swift run tibometer-probe
swift run tibometer-probe --recent-threads
swift run tibometer-probe --thread-usage <existing-task-id>
```

Task usage comes exclusively from the returned `threadUsage`; when absent, the result is `available: false`. Available data preserves model metadata, token breakdowns, and estimated costs in the API's original units.

## Localization and releases

Translations live in `Sources/TibometerCore/Resources/<language>.lproj/Localizable.strings`. All 16 catalogs must share the same keys and numbered placeholders. A new language also needs an `AppLanguage` case, locale and website route mapping, and a `CFBundleLocalizations` entry.

Follow [Releasing](releasing.md) to prepare a release.
