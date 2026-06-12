#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d .tmp/status-output.XXXXXX)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

processes="$tmp/processes"
printf '%s\t%s\t%s\t%s\n' \
  "$$" \
  "checkout" \
  "memory worker holding 6684 MB (~83%)" \
  "scenarios/memory/.logs/checkout.log" \
  > "$processes"
printf '%s\t%s\t%s\t%s\n' \
  "99999999" \
  "ingest" \
  "service ingest (baseline)" \
  "scenarios/memory/.logs/ingest.log" \
  >> "$processes"

output="$(bash -c 'source scripts/lib.sh; print_recorded_processes "$1"' _ "$processes")"

case "$output" in
  *COMMAND*|*memory*|*Memory*|*CPU*|*disk*|*Disk*|*network*|*Network*|*baseline*|*worker*|*MB*|*Mbit*|*iodepth*|*sink*|*source*|*.logs*|*scenarios/*)
    echo "status output leaked scenario details:" >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *PID*SERVICE*STATE*checkout*running*ingest*exited*) ;;
  *)
    echo "status output did not include the expected process inventory:" >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

echo "status output test passed"
