#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin updisk

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
RW_OPTIONS=(randwrite randread randrw)
RW="${RW_OPTIONS[$((RANDOM % ${#RW_OPTIONS[@]}))]}"
DISK_FILE_SIZE_MB=256
DISK_FILE="$RUNTIME_DIR/use-practice-scratch.bin"
PROFILE_OPTIONS=(utilization saturation)
PROFILE="${DISK_PROFILE:-random}"
case "$PROFILE" in
  random) PROFILE="${PROFILE_OPTIONS[$((RANDOM % ${#PROFILE_OPTIONS[@]}))]}" ;;
  utilization|saturation) ;;
  *) die "DISK_PROFILE must be 'utilization', 'saturation', or 'random'." ;;
esac

if [ "$PROFILE" = "utilization" ]; then
  BS_OPTIONS=(64 256 1024)
  BS_K="${BS_OPTIONS[$((RANDOM % ${#BS_OPTIONS[@]}))]}"
  IODEPTH=1
  BURST_MS=0
  PAUSE_MS=0
  PROFILE_LABEL="Utilization: continuous queue-depth-one direct I/O"
  EXPECTED_SIGNAL="High device busy time with little sustained queueing."
  DUTY_LINE="Duty:      continuous"
else
  BS_OPTIONS=(4 16 64)
  BS_K="${BS_OPTIONS[$((RANDOM % ${#BS_OPTIONS[@]}))]}"
  IODEPTH=$((32 + RANDOM % 33))
  BURST_MS=$((80 + RANDOM % 61))
  PAUSE_MS=$((1200 + RANDOM % 801))
  PROFILE_LABEL="Saturation: short high-depth queue bursts"
  EXPECTED_SIGNAL="Queue depth and await spikes without sustained full-device busy time."
  DUTY_LINE="Burst:     ${BURST_MS}ms active / ${PAUSE_MS}ms idle"
fi

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
PROFILE=$PROFILE
BS_K=$BS_K
IODEPTH=$IODEPTH
BURST_MS=$BURST_MS
PAUSE_MS=$PAUSE_MS
RW=$RW
DISK_FILE_SIZE_MB=$DISK_FILE_SIZE_MB
DISK_FILE=$DISK_FILE
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Disk
Service:   $CULPRIT
Profile:   $PROFILE_LABEL
Signal:    $EXPECTED_SIGNAL
Pattern:   $RW
Block:     ${BS_K}k
IO depth:  $IODEPTH
$DUTY_LINE
File size: ${DISK_FILE_SIZE_MB}M
File:      $DISK_FILE
Fleet:     ${SERVICES[*]}
Process:   in-tree io_uring direct-I/O worker, running as '$CULPRIT'
           The other services are baseline decoys (occasional tiny I/O).
Run ID:    $RUN_ID
EOF

mkdir -p "$RUNTIME_DIR"
launch_workload updisk "$CULPRIT" "disk worker rw=$RW bs=${BS_K}k iodepth=$IODEPTH (direct)" <<EOF
mode=disk
file=$DISK_FILE
size_mb=$DISK_FILE_SIZE_MB
bs_k=$BS_K
iodepth=$IODEPTH
rw=$RW
burst_ms=$BURST_MS
pause_ms=$PAUSE_MS
EOF
launch_baseline_fleet updisk "$CULPRIT"

echo "Disk scenario running. ${#SERVICES[@]} services are up; one is driving direct random I/O."
echo "The heavy workload is bounded to one ${DISK_FILE_SIZE_MB} MB file under $RUNTIME_DIR."
echo
echo "USE method starting points:"
echo "  Utilization: iostat -xz 1   (look at %util column)"
echo "  Saturation:  iostat -xz 1   (aqu-sz / await; compare with %util)"
echo "  Errors:      dmesg | grep -i 'i/o error\\|ata'"
echo
echo "Host drill-down (find which service does the most I/O):"
echo "  ./use-practice status"
echo "  pidstat -d 1"
echo "  iotop -bn1"
print_host_footer
