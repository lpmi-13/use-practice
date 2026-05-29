#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

need_cmd stress-ng

start_run 1
CULPRIT="$(pick_random_service)"
CPU_METHODS=(matrixprod ackermann bitops crc16)
CPU_METHOD="${CPU_METHODS[$((RANDOM % ${#CPU_METHODS[@]}))]}"
WORKERS=$((1 + RANDOM % 4))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
WORKERS=$WORKERS
CPU_METHOD=$CPU_METHOD
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  CPU
Service:   $CULPRIT
Workers:   $WORKERS
Method:    $CPU_METHOD
Process:   stress-ng --cpu $WORKERS --cpu-method $CPU_METHOD
Run ID:    $RUN_ID
EOF

start_service \
  "$CULPRIT" \
  "stress-ng --cpu $WORKERS --cpu-method $CPU_METHOD" \
  "exec -a \"\$0\" stress-ng --cpu \"$WORKERS\" --cpu-method \"$CPU_METHOD\" --metrics-brief"

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
