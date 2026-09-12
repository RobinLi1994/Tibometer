# Tibometer

<img src="Sources/Tibometer/Resources/Logo.png" alt="Tibometer" width="80">

A tiny Codex usage monitor

[官网](https://tibometer.app/zh/) · [English](README.md)

## 功能

- 菜单栏显示 **5H**、**7D** 剩余额度，可单独或同时显示。
- 百分比、进度条、进度条加百分比、进度环、进度环加百分比五种样式。
- 查看重置时间和额外点数，额度重置时发送通知。
- 支持通用 JSON、Slack、Discord、飞书 / Lark 和企业微信 Webhook。
- 支持 16 种语言，可跟随系统或手动切换。

> Tibo 又出手了。
> 你的 Codex 额度已重置为 100%。

## 安装

需要 macOS 14 或更新版本，以及已登录 ChatGPT 账号的 Codex。源码构建需要带有 Swift 5.9 或更新版本的 Apple Command Line Tools。

在源码目录运行：

```bash
./scripts/install.sh
```

脚本会构建并安装到 `~/Applications/Tibometer.app`。更新前请先退出正在运行的 Tibometer。

若未自动找到 Codex，可在「设置 → 数据源」中手动选择。

## 通知与 Webhook

在「设置 → 通知」中开启重置提醒。

在「设置 → Webhook」中选择格式、填写地址、启用投递并保存。签名配置和消息格式见 [Webhook 配置](docs/webhooks.md)。

## 数据读取

Tibometer 通过本机 Codex 应用读取额度。设置和重置记录保存在 Mac 上，可选的 Webhook 向你配置的地址发送提醒。

## 开发

```bash
./scripts/test.sh
./scripts/build-app.sh
```

另见 [贡献指南](CONTRIBUTING.md)、[验证说明](qa/verification.md)、[发布说明](docs/releasing.md) 和 [更新记录](CHANGELOG.md)。

## 协议

[MIT](LICENSE)

GitHub 图标：[Octicons MIT 许可证](Sources/Tibometer/Resources/Octicons-LICENSE.txt)。
