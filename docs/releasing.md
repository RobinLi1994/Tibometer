# Releasing Tibometer

## Prepare

Update the version in `Resources/Info.plist`, `CodexClient.swift`, `Webhook.swift`, and `CHANGELOG.md`. Keep the release notes in `docs/releases/v<version>.md` aligned with the actual download architecture and signing status.

Run the checks from a clean checkout:

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/package-release.sh
```

Release files are written to `dist/releases/v<version>/`.

The default build uses an ad-hoc signature. For Developer ID distribution, enable Hardened Runtime and timestamping when signing, then notarize and staple the app before packaging. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Keep signing certificates and credentials outside the repository.

Complete [verification](../qa/verification.md) and check the commit and release files for private data.

## Create the GitHub draft

After the source commit has been pushed and CI succeeds, create and push an annotated tag for that exact commit. For version 1.0.0:

```bash
git tag -a v1.0.0 -m "Tibometer v1.0.0"
git push origin v1.0.0
gh release create v1.0.0 \
  dist/releases/v1.0.0/Tibometer-1.0.0-macOS-arm64.zip \
  dist/releases/v1.0.0/SHA256SUMS \
  --repo nangcr/Tibometer \
  --verify-tag \
  --draft \
  --title "Tibometer v1.0.0" \
  --notes-file docs/releases/v1.0.0.md
```

Check the attached ZIP, checksum, and signing status before publishing the draft.
