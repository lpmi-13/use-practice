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
MIN_MB=256
if [ "$HOST_MEM_MB" -lt 1024 ]; then
  MIN_MB=128
fi
MAX_MB=$((HOST_MEM_MB / 3))
if [ "$MAX_MB" -lt "$MIN_MB" ]; then
  MAX_MB="$MIN_MB"
fi
RANGE=$((MAX_MB - MIN_MB + 1))
MEM_MB=$((MIN_MB + RANDOM % RANGE))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
MEM_MB=$MEM_MB
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Memory
Service:   $CULPRIT
Resident:  ${MEM_MB} MB
Fleet:     ${SERVICES[*]}
Process:   in-tree memory worker holding ${MEM_MB} MB resident, running as '$CULPRIT'
           The other services are baseline decoys (small steady RSS).
Run ID:    $RUN_ID
EOF

launch_workload uworker "$CULPRIT" "memory worker holding ${MEM_MB} MB" <<EOF
mode=mem
mb=$MEM_MB
touch_ms=1000
EOF
launch_baseline_fleet uworker "$CULPRIT"

echo "Memory scenario running. ${#SERVICES[@]} services are up; one holds a large resident set."
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
