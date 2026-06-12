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
PROFILE_OPTIONS=(resident pressure)
PROFILE="${MEM_PROFILE:-random}"
case "$PROFILE" in
  random) PROFILE="${PROFILE_OPTIONS[$((RANDOM % ${#PROFILE_OPTIONS[@]}))]}" ;;
  resident|pressure) ;;
  *) die "MEM_PROFILE must be 'resident', 'pressure', or 'random'." ;;
esac

if [ "$PROFILE" = "resident" ]; then
  # High resident usage with a quieter touch cadence: this should make
  # MemAvailable small after settling, without continuously forcing reclaim.
  TARGET_PCT=$((80 + RANDOM % 4))   # aim for 80-83%
  RESERVE_MB=$((HOST_MEM_MB / 6))
  if [ "$RESERVE_MB" -lt 768 ]; then
    RESERVE_MB=768
  fi
  TOUCH_MS=10000
  CHURN_MB=0
  BURST_MS=0
  PAUSE_MS=0
  PROFILE_LABEL="Resident set: high utilization, low expected saturation"
  EXPECTED_SIGNAL="Low available memory with quiet vmstat si/so and low memory PSI after the initial allocation settles."
  CHURN_LINE="Churn:     none"
else
  # Keep the current high-utilization shape, then add bounded mmap churn to
  # create active reclaim stalls. The churn is intentionally smaller than the
  # reserved headroom so it should create pressure without aiming for OOM.
  TARGET_PCT=$((82 + RANDOM % 6))   # aim for 82-87%
  RESERVE_MB=$((HOST_MEM_MB / 6))
  if [ "$RESERVE_MB" -lt 512 ]; then
    RESERVE_MB=512
  fi
  TOUCH_MS=1000
  CHURN_MB=$((HOST_MEM_MB / 48))
  if [ "$CHURN_MB" -lt 64 ]; then
    CHURN_MB=64
  fi
  if [ "$CHURN_MB" -gt 192 ]; then
    CHURN_MB=192
  fi
  BURST_MS=750
  PAUSE_MS=250
  PROFILE_LABEL="Pressure: high utilization plus reclaim stalls"
  EXPECTED_SIGNAL="Low available memory with memory PSI some/full or swap si/so activity during churn."
  CHURN_LINE="Churn:     ${CHURN_MB} MB chunks, ${BURST_MS}ms active / ${PAUSE_MS}ms idle"
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
PROFILE=$PROFILE
MEM_MB=$MEM_MB
MEM_PCT=$MEM_PCT
TOUCH_MS=$TOUCH_MS
CHURN_MB=$CHURN_MB
BURST_MS=$BURST_MS
PAUSE_MS=$PAUSE_MS
HOST_MEM_MB=$HOST_MEM_MB
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Memory
Service:   $CULPRIT
Profile:   $PROFILE_LABEL
Signal:    $EXPECTED_SIGNAL
Resident:  ${MEM_MB} MB (~${MEM_PCT}% of ${HOST_MEM_MB} MB host RAM)
$CHURN_LINE
Fleet:     ${SERVICES[*]}
Process:   in-tree memory worker holding ${MEM_MB} MB resident, running as '$CULPRIT'
           The other services are baseline decoys (small steady RSS).
Run ID:    $RUN_ID
EOF

launch_workload uworker "$CULPRIT" "memory worker holding ${MEM_MB} MB (~${MEM_PCT}%)" <<EOF
mode=mem
profile=$PROFILE
mb=$MEM_MB
touch_ms=$TOUCH_MS
churn_mb=$CHURN_MB
burst_ms=$BURST_MS
pause_ms=$PAUSE_MS
EOF
launch_baseline_fleet uworker "$CULPRIT"

echo "Memory scenario running. ${#SERVICES[@]} services are up; one is stressing host memory."
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
