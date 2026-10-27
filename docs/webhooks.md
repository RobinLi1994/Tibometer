# Webhook configuration

In Settings → Webhook, choose a format, enter a URL, enable delivery, and save. Use Send Test to check the destination.

Supported formats are generic JSON, Slack, Discord, Feishu / Lark, WeCom, and DingTalk. Feishu supports optional bot signing secrets; DingTalk requires a signing secret. If a receiver requires keywords, allow `Codex` and `Tibometer` so both reset and test messages are accepted.

For a [DingTalk custom group robot](https://open.dingtalk.com/document/orgapp/custom-robot-access), choose the signing security mode, paste its Webhook URL (including `access_token`), and enter the `SEC` signing secret in Settings. Tibometer signs each delivery with the current Unix millisecond timestamp and adds `timestamp` and URL-encoded `sign` query parameters. DingTalk receives a text message; a nonzero `errcode` is reported as a rejected delivery.

## Reset messages

English reset alerts begin with:

```text
Tibo did it again.
Your Codex usage has been reset to 100%.
Weekly limit
```

Messages follow the app language. The JSON `remaining_percent` field carries the observed remaining quota.

## Generic JSON

```json
{
  "schema_version": 1,
  "event": "codex.limit.reset",
  "event_id": "61CB95B8-871D-4CA7-8B0F-DF1ED4CB8C72",
  "observed_at": "2026-09-12T12:00:00Z",
  "bucket_id": "codex",
  "bucket_name": "Codex",
  "window": "five_hour",
  "window_duration_mins": 300,
  "previous_used_percent": 85,
  "remaining_percent": 100,
  "previous_reset_at": "2026-09-12T12:00:00Z",
  "next_reset_at": "2026-09-12T17:00:00Z",
  "reason": "restored_to_full",
  "message": "Tibo did it again.\nYour Codex usage has been reset to 100%.\n5-hour limit"
}
```

`window` is `five_hour` or `weekly`. `reason` is `restored_to_full` or `new_window`. Test messages use `codex.webhook.test`. Missing reset timestamps are omitted.

## Authentication and signatures

An optional bearer token is sent as `Authorization: Bearer …`. Generic JSON can also be signed with HMAC-SHA256:

```text
X-Tibometer-Timestamp: <Unix seconds>
X-Tibometer-Signature: sha256=<HMAC-SHA256(secret, timestamp + "." + raw body), hex>
X-Tibometer-Event-ID: <event ID>
Idempotency-Key: <event ID>
```

Verify the exact request bytes, timestamp, and event ID at the receiver. Feishu and DingTalk use their own bot signature formats.

## Delivery

Network failures, HTTP 429, and HTTP 5xx are retried up to three attempts, with 60- and 120-second delays. Other HTTP errors and bot rejections stop delivery and appear in Recent Resets. Pending deliveries survive restarts. Changing the destination or format cancels deliveries queued for the previous configuration.

Delivery is at least once: a lost response can result in a retry. Deduplicate by event ID. Only HTTPS and loopback HTTP URLs are accepted; redirects are rejected. Payloads contain quota data and timestamps, with account identity and authentication credentials excluded.
