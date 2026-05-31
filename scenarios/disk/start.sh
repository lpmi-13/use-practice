#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin updisk

start_run "$((5 + RANDOM % 6))"
CULPRIT="$(pick_random_service)"
BS_OPTIONS=(4 16 64 256)
BS_K="${BS_OPTIONS[$((RANDOM % ${#BS_OPTIONS[@]}))]}"
IODEPTH=$((8 + RANDOM % 25))
RW_OPTIONS=(randwrite randread randrw)
RW="${RW_OPTIONS[$((RANDOM % ${#RW_OPTIONS[@]}))]}"
DISK_FILE_SIZE_MB=256
DISK_FILE="$RUNTIME_DIR/use-practice-scratch.bin"

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
BS_K=$BS_K
IODEPTH=$IODEPTH
RW=$RW
DISK_FILE_SIZE_MB=$DISK_FILE_SIZE_MB
DISK_FILE=$DISK_FILE
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Disk
Service:   $CULPRIT
Pattern:   $RW
Block:     ${BS_K}k
IO depth:  $IODEPTH
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
EOF
launch_baseline_fleet updisk "$CULPRIT"

echo "Disk scenario running. ${#SERVICES[@]} services are up; one is driving direct random I/O."
echo "The heavy workload is bounded to one ${DISK_FILE_SIZE_MB} MB file under $RUNTIME_DIR."
echo
echo "USE method starting points:"
echo "  Utilization: iostat -xz 1   (look at %util column)"
echo "  Saturation:  iostat -xz 1   (aqu-sz / await rising)"
echo "  Errors:      dmesg | grep -i 'i/o error\\|ata'"
echo
echo "Host drill-down (find which service does the most I/O):"
echo "  ./use-practice status"
echo "  pidstat -d 1"
echo "  iotop -bn1"
print_host_footer
