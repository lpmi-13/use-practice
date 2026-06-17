#!/usr/bin/env bash
# Run live smoke tests against a running iximiuz Labs playground session.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/smoke-iximiuz-live.sh <playground-session-id>

Environment:
  MACHINE=lab-01              Target machine name.
  LAB_USER=laborant           SSH user.
  WAIT_LAB_READY=1            Wait for the lab bootstrap ready marker.
  REQUIRE_NETWORK_VETH=1      Fail if network uses loopback fallback.
  RUN_CPU_KERNELWAIT=1        Run cpu -> kernelwait.
  RUN_DISK_SATURATION=1       Run disk -> saturation.
  RUN_NETWORK_HIGHLOAD=1      Run network -> highload.
  RUN_MEMORY_OOM=1            Run memory -> oom and require oom_kill.

This script assumes the playground is already running and initialized. Start one
with labctl after publishing/updating the manifest, for example:

  labctl playground start use-practice-4ce4816f --file playground/iximiuz/manifest.yaml --quiet --safety-disclaimer-consent
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

playground_id="${1:-}"
[ -n "$playground_id" ] || {
  usage >&2
  exit 1
}

machine="${MACHINE:-lab-01}"
user="${LAB_USER:-laborant}"
require_network_veth="${REQUIRE_NETWORK_VETH:-1}"
remote_script="/tmp/use-practice-iximiuz-live-smoke.sh"
local_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/iximiuz-live-smoke-remote.sh"

command -v labctl >/dev/null 2>&1 || {
  echo "labctl is required" >&2
  exit 1
}

labctl cp \
  --machine "$machine" \
  --user "$user" \
  "$local_script" \
  "${playground_id}:${remote_script}"

labctl ssh \
  --machine "$machine" \
  --user "$user" \
  "$playground_id" \
  -- env \
    WAIT_LAB_READY="${WAIT_LAB_READY:-1}" \
    REQUIRE_NETWORK_VETH="$require_network_veth" \
    RUN_CPU_KERNELWAIT="${RUN_CPU_KERNELWAIT:-1}" \
    RUN_DISK_SATURATION="${RUN_DISK_SATURATION:-1}" \
    RUN_NETWORK_HIGHLOAD="${RUN_NETWORK_HIGHLOAD:-1}" \
    RUN_MEMORY_OOM="${RUN_MEMORY_OOM:-1}" \
    bash "$remote_script"
