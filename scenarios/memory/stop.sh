#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose down --remove-orphans >/dev/null 2>&1 || true
rm -f .env .answer
echo "Memory scenario stopped."
