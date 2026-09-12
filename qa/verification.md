# Verification

## Automated checks

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/package-release.sh
```

## Manual checks

Check macOS 14 and the current macOS release. Use a dedicated webhook destination for delivery checks.

- Menu bar: five styles, quota selection, missing data, and stale data.
- Panel: anchoring and resizing on small and multiple displays.
- Quota colors: values around the 25% and 50% boundaries.
- Settings: input persistence, ⌘V, Codex selection, and connection feedback.
- Notifications: permission handling, reset delivery, and history.
- Accessibility: keyboard focus, disabled controls, Reduce Motion, and both appearances.
- Languages: system selection, manual switching, and text wrapping.
- Installation: launch the packaged app, check its version, and replace it while retaining settings.
