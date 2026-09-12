# Tibometer

<img src="Sources/Tibometer/Resources/Logo.png" alt="Tibometer" width="80">

A tiny Codex usage monitor

[Website](https://tibometer.app/) · [简体中文](README.zh-CN.md)

## Features

- See either or both **5H** and **7D** limits in the macOS menu bar.
- Choose percentages, bars, bars with percentages, rings, or rings with percentages.
- View reset times and extra credits, and get notified when limits reset.
- Send reset alerts through JSON, Slack, Discord, Feishu / Lark, or WeCom webhooks.
- 16 languages, with system detection and manual selection.

> Tibo did it again.
> Your Codex usage has been reset to 100%.

## Install

Requires macOS 14 or later and Codex signed in with a ChatGPT account. Building requires Apple Command Line Tools with Swift 5.9 or later.

From a local checkout:

```bash
./scripts/install.sh
```

The script builds and installs `~/Applications/Tibometer.app`. Quit an existing Tibometer instance before installing an update.

If Codex is not found automatically, select it in Settings → Data Source.

## Notifications and webhooks

Enable reset alerts in Settings → Notifications.

In Settings → Webhook, choose a format, enter the URL, enable delivery, and save. Signing settings and payload details are in [Webhook configuration](docs/webhooks.md).

## Data access

Tibometer reads quotas through your local Codex app. Settings and reset history stay on your Mac; optional webhooks send alerts to your configured destination.

## Development

```bash
./scripts/test.sh
./scripts/build-app.sh
```

See [Contributing](CONTRIBUTING.md), [verification](qa/verification.md), [release preparation](docs/releasing.md), and the [changelog](CHANGELOG.md).

## License

[MIT](LICENSE)

GitHub icon: [Octicons MIT License](Sources/Tibometer/Resources/Octicons-LICENSE.txt).
