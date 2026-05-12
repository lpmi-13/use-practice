#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for s in cpu memory disk network hotpath; do
  (cd "scenarios/$s" && ./stop.sh) || true
done
rm -f .active-scenario
