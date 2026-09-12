#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run tibometer-tests
python3 scripts/verify-webhook.py
