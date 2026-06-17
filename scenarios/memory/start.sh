#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin uworker

cgroup_write() {
  local path="$1"
  local value="$2"
  if [ -w "$path" ]; then
    printf '%s\n' "$value" > "$path"
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || return 1
  printf '%s\n' "$value" | sudo -n tee "$path" >/dev/null
}

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
HOST_MEM_MB="$(awk '/MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
HOST_MEM_MB="${HOST_MEM_MB:-2048}"
HOST_AVAIL_MB="$(awk '/MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)"
HOST_AVAIL_MB="${HOST_AVAIL_MB:-$((HOST_MEM_MB * 3 / 4))}"
PROFILE_OPTIONS=(resident pressure oom)
PROFILE="${MEM_PROFILE:-random}"
case "$PROFILE" in
  random) PROFILE="${PROFILE_OPTIONS[$((RANDOM % ${#PROFILE_OPTIONS[@]}))]}" ;;
  resident|pressure|oom) ;;
  *) die "MEM_PROFILE must be 'resident', 'pressure', 'oom', or 'random'." ;;
esac

if [ "$PROFILE" = "oom" ]; then
  CGROUP_ROOT="${CGROUP_ROOT:-/sys/fs/cgroup}"
  [ -f "$CGROUP_ROOT/cgroup.controllers" ] || die "MEM_PROFILE=oom requires cgroup v2 at $CGROUP_ROOT."
  if ! grep -qw memory "$CGROUP_ROOT/cgroup.controllers"; then
    die "MEM_PROFILE=oom requires the cgroup v2 memory controller."
  fi
  if ! grep -qw memory "$CGROUP_ROOT/cgroup.subtree_control"; then
    if [ -w "$CGROUP_ROOT/cgroup.subtree_control" ]; then
      printf '+memory\n' > "$CGROUP_ROOT/cgroup.subtree_control" 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
      printf '+memory\n' | sudo -n tee "$CGROUP_ROOT/cgroup.subtree_control" >/dev/null 2>&1 || true
    fi
  fi

  CGROUP_DIR="$CGROUP_ROOT/use-practice-$RUN_ID-$CULPRIT-oom"
  if ! mkdir "$CGROUP_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1 && sudo -n mkdir "$CGROUP_DIR" 2>/dev/null; then
      sudo -n chown "$(id -u):$(id -g)" "$CGROUP_DIR" || die "failed to chown $CGROUP_DIR."
    else
      die "MEM_PROFILE=oom requires permission to create $CGROUP_DIR."
    fi
  fi
  echo "$CGROUP_DIR" > .cgroups

  OOM_LIMIT_PCT="${OOM_LIMIT_PCT:-80}"
  case "$OOM_LIMIT_PCT" in
    ''|*[!0-9]*) die "OOM_LIMIT_PCT must be an integer from 10 to 90." ;;
  esac
  if [ "$OOM_LIMIT_PCT" -lt 10 ] || [ "$OOM_LIMIT_PCT" -gt 90 ]; then
    die "OOM_LIMIT_PCT must be an integer from 10 to 90."
  fi

  EFFECTIVE_AVAIL_MB="$HOST_AVAIL_MB"
  PARENT_LIMIT="$(cat "$CGROUP_ROOT/memory.max" 2>/dev/null || true)"
  if [ -n "$PARENT_LIMIT" ] && [ "$PARENT_LIMIT" != "max" ]; then
    PARENT_LIMIT_MB=$((PARENT_LIMIT / 1024 / 1024))
    if [ "$PARENT_LIMIT_MB" -gt 0 ] && [ "$PARENT_LIMIT_MB" -lt "$EFFECTIVE_AVAIL_MB" ]; then
      EFFECTIVE_AVAIL_MB="$PARENT_LIMIT_MB"
    fi
  fi

  RESERVE_MB="${OOM_RESERVE_MB:-$((HOST_MEM_MB / 10))}"
  case "$RESERVE_MB" in
    ''|*[!0-9]*) die "OOM_RESERVE_MB must be a positive integer." ;;
  esac
  if [ "$RESERVE_MB" -lt 1 ]; then
    die "OOM_RESERVE_MB must be a positive integer."
  fi
  if [ "$RESERVE_MB" -lt 512 ]; then
    RESERVE_MB=512
  fi
  CAP_MB=$((HOST_MEM_MB - RESERVE_MB))
  LIMIT_MB=$((EFFECTIVE_AVAIL_MB * OOM_LIMIT_PCT / 100))
  if [ "$LIMIT_MB" -gt "$CAP_MB" ]; then
    LIMIT_MB="$CAP_MB"
  fi
  if [ "$LIMIT_MB" -lt 128 ]; then
    die "MEM_PROFILE=oom needs at least 128 MB after reserving ${RESERVE_MB} MB for the host."
  fi
  OOM_MB=$((LIMIT_MB + LIMIT_MB / 4))
  if [ "$OOM_MB" -lt $((LIMIT_MB + 128)) ]; then
    OOM_MB=$((LIMIT_MB + 128))
  fi

  # Set a large but bounded memory cgroup and disable cgroup-local swap where
  # supported, so the child is killed by memcg OOM instead of swapping
  # indefinitely or competing with the whole host.
  cgroup_write "$CGROUP_DIR/memory.max" "$((LIMIT_MB * 1024 * 1024))" || die "failed to set $CGROUP_DIR/memory.max."
  if [ -f "$CGROUP_DIR/memory.swap.max" ]; then
    cgroup_write "$CGROUP_DIR/memory.swap.max" 0 || die "failed to set $CGROUP_DIR/memory.swap.max."
  fi
  if [ -f "$CGROUP_DIR/memory.oom.group" ]; then
    cgroup_write "$CGROUP_DIR/memory.oom.group" 1 || true
  fi

  MEM_MB=$OOM_MB
  MEM_PCT=$((MEM_MB * 100 / HOST_MEM_MB))
  TOUCH_MS=10000
  CHURN_MB=0
  BURST_MS=0
  PAUSE_MS=0
  PROFILE_LABEL="OOM kill: persistent memcg OOM from a constrained child worker"
  EXPECTED_SIGNAL="Repeated cgroup OOM kills for the culprit service; memory.events oom_kill increases persistently."
  CHURN_LINE="Cgroup:   $CGROUP_DIR memory.max=${LIMIT_MB} MB (${OOM_LIMIT_PCT}% of available, reserve ${RESERVE_MB} MB), child target=${OOM_MB} MB"
elif [ "$PROFILE" = "resident" ]; then
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
if [ "$PROFILE" != "oom" ]; then
  MEM_MB=$((HOST_MEM_MB * TARGET_PCT / 100))
  CAP_MB=$((HOST_MEM_MB - RESERVE_MB))
  if [ "$MEM_MB" -gt "$CAP_MB" ]; then
    MEM_MB="$CAP_MB"
  fi
  if [ "$MEM_MB" -lt 64 ]; then
    MEM_MB=64
  fi
  MEM_PCT=$((MEM_MB * 100 / HOST_MEM_MB))
fi

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
HOST_AVAIL_MB=$HOST_AVAIL_MB
CGROUP_DIR=${CGROUP_DIR:-}
LIMIT_MB=${LIMIT_MB:-}
OOM_LIMIT_PCT=${OOM_LIMIT_PCT:-}
RESERVE_MB=${RESERVE_MB:-}
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

if [ "$PROFILE" = "oom" ]; then
  ACTIVE_BIN="$(stage_workload uworker "$CULPRIT" <<EOF
mode=mem
profile=$PROFILE
mb=$MEM_MB
touch_ms=$TOUCH_MS
churn_mb=$CHURN_MB
burst_ms=$BURST_MS
pause_ms=$PAUSE_MS
EOF
)"
  CFG_PATH="$RUNTIME_DIR/bin/$CULPRIT.oom.cfg"
  start_service "$CULPRIT" "memory worker repeatedly OOM-killed in ${LIMIT_MB} MB cgroup" '
while :; do
  cat > "'"$CFG_PATH"'" <<CFG
mode=mem
profile=resident
mb='"$OOM_MB"'
touch_ms=10000
start_delay_ms=750
CFG
  UP_CFG="'"$CFG_PATH"'" "'"$ACTIVE_BIN"'" &
  child=$!
  if [ -w "'"$CGROUP_DIR"'/cgroup.procs" ]; then
    printf "%s\n" "$child" > "'"$CGROUP_DIR"'/cgroup.procs" || exit 90
  else
    printf "%s\n" "$child" | sudo -n tee "'"$CGROUP_DIR"'/cgroup.procs" >/dev/null || exit 90
  fi
  rc=0
  wait "$child" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 90 ]; then
    exit 1
  fi
  sleep 1
done
'
else
  launch_workload uworker "$CULPRIT" "memory worker holding ${MEM_MB} MB (~${MEM_PCT}%)" <<EOF
mode=mem
profile=$PROFILE
mb=$MEM_MB
touch_ms=$TOUCH_MS
churn_mb=$CHURN_MB
burst_ms=$BURST_MS
pause_ms=$PAUSE_MS
EOF
fi
launch_baseline_fleet uworker "$CULPRIT"

echo "Memory scenario running. ${#SERVICES[@]} services are up; one is stressing host memory."
echo
echo "USE method starting points:"
echo "  Utilization: free -m   (look at used/available)"
echo "  Saturation:  vmstat 1  (si/so swap columns), /proc/pressure/memory"
echo "  Errors:      dmesg | grep -i 'killed process\\|oom'"
if [ "$PROFILE" = "oom" ]; then
  echo "               cat $CGROUP_DIR/memory.events"
fi
echo
echo "Host drill-down (find which service holds the memory):"
echo "  ./use-practice status"
echo "  top -bcn1 w512"
echo "  ps -eo pid,ppid,pgid,stat,pcpu,pmem,rss,args --sort=-rss | head"
print_host_footer
