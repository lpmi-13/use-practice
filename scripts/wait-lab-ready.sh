#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${USE_PRACTICE_READY_TIMEOUT_SECONDS:-240}"
deadline=$((SECONDS + timeout_seconds))
ready_marker="/var/lib/use-practice/ready"

while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$ready_marker" ]; then
    exit 0
  fi
  sleep 2
done

echo "use-practice lab did not become ready within ${timeout_seconds}s" >&2
systemctl status use-practice-bootstrap.service --no-pager >&2 || true
exit 1
