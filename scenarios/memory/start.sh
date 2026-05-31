#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin uworker

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
HOST_MEM_MB="$(awk '/MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
HOST_MEM_MB="${HOST_MEM_MB:-2048}"

# Consume a high, host-relative share of RAM so the pressure is significant on
# both tiny and large VMs. Reserve headroom (the larger of 512 MB or ~1/6 of
# RAM) for the OS, the investigation tools, and the decoy fleet, so the box
# goes "used near total / available tiny" without locking up or OOM-looping.
TARGET_PCT=$((82 + RANDOM % 6))   # aim for 82-87%
RESERVE_MB=$((HOST_MEM_MB / 6))
if [ "$RESERVE_MB" -lt 512 ]; then
  RESERVE_MB=512
fi
MEM_MB=$((HOST_MEM_MB * TARGET_PCT / 100))
CAP_MB=$((HOST_MEM_MB - RESERVE_MB))
if [ "$MEM_MB" -gt "$CAP_MB" ]; then
  MEM_MB="$CAP_MB"
fi
if [ "$MEM_MB" -lt 64 ]; then
  MEM_MB=64
fi
MEM_PCT=$((MEM_MB * 100 / HOST_MEM_MB))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
MEM_MB=$MEM_MB
MEM_PCT=$MEM_PCT
HOST_MEM_MB=$HOST_MEM_MB
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Memory
Service:   $CULPRIT
Resident:  ${MEM_MB} MB (~${MEM_PCT}% of ${HOST_MEM_MB} MB host RAM)
Fleet:     ${SERVICES[*]}
Process:   in-tree memory worker holding ${MEM_MB} MB resident, running as '$CULPRIT'
           The other services are baseline decoys (small steady RSS).
Run ID:    $RUN_ID
EOF

launch_workload uworker "$CULPRIT" "memory worker holding ${MEM_MB} MB (~${MEM_PCT}%)" <<EOF
mode=mem
mb=$MEM_MB
touch_ms=1000
EOF
launch_baseline_fleet uworker "$CULPRIT"

echo "Memory scenario running. ${#SERVICES[@]} services are up; one holds ~${MEM_PCT}% of host RAM."
echo
echo "USE method starting points:"
echo "  Utilization: free -m   (look at used/available)"
echo "  Saturation:  vmstat 1  (si/so swap columns), /proc/pressure/memory"
echo "  Errors:      dmesg | grep -i 'killed process\\|oom'"
echo
echo "Host drill-down (find which service holds the memory):"
echo "  ./use-practice status"
echo "  top -bcn1 w512"
echo "  ps -eo pid,ppid,pgid,stat,pcpu,pmem,rss,args --sort=-rss | head"
print_host_footer
