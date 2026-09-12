# Contributing

Build on macOS 14 or later with Apple Command Line Tools and Swift 5.9 or later. Python 3 is used for the stdio and HTTP fixtures.

```bash
./scripts/test.sh
./scripts/build-app.sh
```

Pull requests should describe the change and how it was checked. Add regression coverage for parsing, reset detection, delivery, or concurrency changes.

Preserve the Codex request allowlist and the distinction between unavailable quota and a real zero. Keep keys and numbered placeholders aligned across all 16 localization catalogs. Use synthetic data and loopback receivers in tests.

Bug reports should include reproduction steps, expected behavior, and the macOS version. Remove account details and webhook credentials from attached logs.

See [Development](docs/development.md). Contributions use the [MIT License](LICENSE).
