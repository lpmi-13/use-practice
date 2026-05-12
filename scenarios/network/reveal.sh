#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f .answer ]; then
  echo "No active scenario. Run ./start.sh first."
  exit 1
fi
cat .answer
