#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

need_cmd stress-ng

start_run 1
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
VM_WORKERS=$((1 + RANDOM % 2))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
MEM_MB=$MEM_MB
VM_WORKERS=$VM_WORKERS
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Memory
Service:   $CULPRIT
Resident:  ${MEM_MB} MB
VMs:       $VM_WORKERS
Process:   stress-ng --vm $VM_WORKERS --vm-bytes ${MEM_MB}m --vm-keep
Run ID:    $RUN_ID
EOF

start_service \
  "$CULPRIT" \
  "stress-ng --vm $VM_WORKERS --vm-bytes ${MEM_MB}m --vm-keep" \
  "exec -a \"\$0\" stress-ng --vm \"$VM_WORKERS\" --vm-bytes \"${MEM_MB}m\" --vm-hang 0 --vm-keep"

echo "Memory scenario running. Service '$CULPRIT' is holding a large resident set."
echo
echo "USE method starting points:"
echo "  Utilization: free -m   (look at used/available)"
echo "  Saturation:  vmstat 1  (si/so swap columns), /proc/pressure/memory"
echo "  Errors:      dmesg | grep -i 'killed process\\|oom'"
echo
echo "Host drill-down:"
echo "  ./use-practice status"
echo "  top -bcn1 w512"
echo "  ps -eo pid,ppid,pgid,stat,pcpu,pmem,rss,args --sort=-rss | head"
print_host_footer
