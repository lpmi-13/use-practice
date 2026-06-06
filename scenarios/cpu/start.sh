#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
PROFILE_OPTIONS=(runq kernelwait)
PROFILE="${CPU_PROFILE:-random}"
case "$PROFILE" in
  random) PROFILE="${PROFILE_OPTIONS[$((RANDOM % ${#PROFILE_OPTIONS[@]}))]}" ;;
  runq|kernelwait) ;;
  *) die "CPU_PROFILE must be 'runq', 'kernelwait', or 'random'." ;;
esac

CPUS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
case "$CPUS" in
  ''|*[!0-9]*) CPUS=1 ;;
esac
[ "$CPUS" -lt 1 ] && CPUS=1

cap_count() {
  local value="$1"
  local cap="$2"
  if [ "$value" -gt "$cap" ]; then
    echo "$cap"
  else
    echo "$value"
  fi
}

if [ "$PROFILE" = "runq" ]; then
  require_workload_bin uworker

  WORKERS=$((CPUS * (2 + RANDOM % 3) + RANDOM % CPUS))
  WORKERS="$(cap_count "$WORKERS" 64)"
  [ "$WORKERS" -le "$CPUS" ] && WORKERS=$((CPUS + 1))

  cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
PROFILE=$PROFILE
CPUS=$CPUS
WORKERS=$WORKERS
SERVICES=${SERVICES[*]}
EOF
  echo "$RUN_ID" > .run-id

  cat > .answer <<EOF
Resource:  CPU
Service:   $CULPRIT
Profile:   Runnable run-queue pressure
CPUs:      $CPUS
Workers:   $WORKERS runnable busy threads
Fleet:     ${SERVICES[*]}
Process:   in-tree CPU worker ($WORKERS busy threads), running as '$CULPRIT'
           The other services are baseline decoys (<1% CPU).
Run ID:    $RUN_ID
EOF

  launch_workload uworker "$CULPRIT" "CPU run queue worker x$WORKERS" <<EOF
mode=cpu
workers=$WORKERS
EOF
  launch_baseline_fleet uworker "$CULPRIT"

  echo "CPU scenario running. ${#SERVICES[@]} services are up; one is creating runnable run-queue pressure."
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
else
  require_workload_bin uwait

  BURNERS=$((CPUS + RANDOM % CPUS))
  BURNERS="$(cap_count "$BURNERS" 32)"
  [ "$BURNERS" -lt 1 ] && BURNERS=1
  WAITERS=$((CPUS * (4 + RANDOM % 5)))
  WAITERS="$(cap_count "$WAITERS" 128)"
  [ "$WAITERS" -lt 8 ] && WAITERS=8
  HOLD_MS=$((4000 + RANDOM % 4000))

  cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
PROFILE=$PROFILE
CPUS=$CPUS
BURNERS=$BURNERS
WAITERS=$WAITERS
HOLD_MS=$HOLD_MS
SERVICES=${SERVICES[*]}
EOF
  echo "$RUN_ID" > .run-id

  cat > .answer <<EOF
Resource:  CPU
Service:   $CULPRIT
Profile:   CPU burners plus non-I/O D-state kernel wait
CPUs:      $CPUS
Burners:   $BURNERS runnable busy threads
D waiters: $WAITERS threads blocked in vfork/kernel_clone
Hold time: ${HOLD_MS}ms per wait cycle
Fleet:     ${SERVICES[*]}
Process:   in-tree kernel-wait worker, running as '$CULPRIT'
           The active service burns CPU and also creates many non-I/O D-state
           threads. The other services are baseline decoys (<1% CPU).
Run ID:    $RUN_ID
EOF

  launch_workload uwait "$CULPRIT" "CPU burners x$BURNERS + D-state waiters x$WAITERS" <<EOF
mode=kernelwait
burners=$BURNERS
waiters=$WAITERS
hold_ms=$HOLD_MS
pause_ms=25
EOF
  launch_baseline_fleet uwait "$CULPRIT"

  echo "CPU scenario running. ${#SERVICES[@]} services are up; one is combining CPU burn with non-I/O D-state kernel waits."
  echo
  echo "USE method starting points:"
  echo "  Utilization: top / htop / mpstat -P ALL 1"
  echo "  Saturation:  vmstat 1   (compare 'r' runnable and 'b' blocked columns)"
  echo "  Load:        uptime / cat /proc/loadavg   (load includes runnable and D-state tasks)"
  echo "  Errors:      dmesg or journalctl -k for hardware/thermal warnings"
  echo
  echo "Host drill-down (separate runnable CPU from non-I/O D wait):"
  echo "  ./use-practice status"
  echo "  top -H -bcn1 w512"
  echo "  ps -eLo pid,tid,ppid,stat,wchan:32,pcpu,comm,args | awk '\$4 ~ /R|D/'"
fi
print_host_footer
