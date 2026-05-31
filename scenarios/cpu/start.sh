#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin upcpu

start_run 1
CULPRIT="$(pick_random_service)"
WORKERS=$((1 + RANDOM % 4))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
WORKERS=$WORKERS
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  CPU
Service:   $CULPRIT
Workers:   $WORKERS
Process:   in-tree CPU worker ($WORKERS busy threads), running as '$CULPRIT'
Run ID:    $RUN_ID
EOF

BINPATH="$(stage_workload upcpu "$CULPRIT" <<EOF
workers=$WORKERS
EOF
)"

start_service \
  "$CULPRIT" \
  "CPU worker x$WORKERS" \
  "exec -a \"\$0\" \"$BINPATH\""

echo "CPU scenario running. Service '$CULPRIT' is consuming CPU on the host."
echo
echo "USE method starting points:"
echo "  Utilization: top / htop / mpstat -P ALL 1"
echo "  Saturation:  vmstat 1   (look at 'r' run-queue column)"
echo "  Errors:      dmesg or journalctl -k for hardware/thermal warnings"
echo
echo "Host drill-down:"
echo "  ./use-practice status"
echo "  top -bcn1 w512"
echo "  ps -eo pid,ppid,pgid,stat,pcpu,pmem,args --sort=-pcpu | head"
print_host_footer
