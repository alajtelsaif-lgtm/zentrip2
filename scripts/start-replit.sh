#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .local/toolchains/jdk/bin/java ]; then
  bash scripts/setup-toolchains.sh
fi
if [ ! -f build/web/index.html ] || [ ! -f backend/target/zentrip-api-1.0.0.jar ]; then
  bash scripts/build-replit.sh
fi
exec python3 scripts/run-replit.py
