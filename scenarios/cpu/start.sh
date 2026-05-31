#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin uworker

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
WORKERS=$((1 + RANDOM % 4))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
WORKERS=$WORKERS
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  CPU
Service:   $CULPRIT
Workers:   $WORKERS
Fleet:     ${SERVICES[*]}
Process:   in-tree CPU worker ($WORKERS busy threads), running as '$CULPRIT'
           The other services are baseline decoys (<1% CPU).
Run ID:    $RUN_ID
EOF

launch_workload uworker "$CULPRIT" "CPU worker x$WORKERS" <<EOF
mode=cpu
workers=$WORKERS
EOF
launch_baseline_fleet uworker "$CULPRIT"

echo "CPU scenario running. ${#SERVICES[@]} services are up; one is consuming CPU."
echo
echo "USE method starting points:"
echo "  Utilization: top / htop / mpstat -P ALL 1"
echo "  Saturation:  vmstat 1   (look at 'r' run-queue column)"
echo "  Errors:      dmesg or journalctl -k for hardware/thermal warnings"
echo
echo "Host drill-down (find which service is hot):"
echo "  ./use-practice status"
echo "  top -bcn1 w512"
echo "  ps -eo pid,ppid,pgid,stat,pcpu,pmem,args --sort=-pcpu | head"
print_host_footer
