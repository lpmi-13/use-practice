#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

need_cmd fio

start_run 1
CULPRIT="$(pick_random_service)"
BS_OPTIONS=(4 16 64 256)
BS_K="${BS_OPTIONS[$((RANDOM % ${#BS_OPTIONS[@]}))]}"
IODEPTH=$((8 + RANDOM % 25))
RW_OPTIONS=(randwrite randread randrw)
RW="${RW_OPTIONS[$((RANDOM % ${#RW_OPTIONS[@]}))]}"
FIO_FILE_SIZE=256M
FIO_FILE="$RUNTIME_DIR/use-practice-fio.bin"

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
BS_K=$BS_K
IODEPTH=$IODEPTH
RW=$RW
FIO_FILE_SIZE=$FIO_FILE_SIZE
FIO_FILE=$FIO_FILE
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Disk
Service:   $CULPRIT
Pattern:   $RW
Block:     ${BS_K}k
IO depth:  $IODEPTH
File size: $FIO_FILE_SIZE
File:      $FIO_FILE
Process:   fio (direct=1, libaio)
Run ID:    $RUN_ID
EOF

fio_script=$(cat <<EOF
mkdir -p "$RUNTIME_DIR"
rm -f "$FIO_FILE"
exec -a "\$0" fio \
  --name=use-practice \
  --filename="$FIO_FILE" \
  --rw="$RW" \
  --bs="${BS_K}k" \
  --size="$FIO_FILE_SIZE" \
  --filesize="$FIO_FILE_SIZE" \
  --time_based \
  --runtime=86400 \
  --direct=1 \
  --ioengine=libaio \
  --iodepth="$IODEPTH" \
  --numjobs=1 \
  --group_reporting
EOF
)

start_service \
  "$CULPRIT" \
  "fio --rw=$RW --bs=${BS_K}k --iodepth=$IODEPTH --direct=1" \
  "$fio_script"

echo "Disk scenario running. Service '$CULPRIT' is driving direct I/O through fio."
echo "Disk footprint is bounded to one ${FIO_FILE_SIZE} file under $RUNTIME_DIR."
echo
echo "USE method starting points:"
echo "  Utilization: iostat -xz 1   (look at %util column)"
echo "  Saturation:  iostat -xz 1   (aqu-sz / await rising)"
echo "  Errors:      dmesg | grep -i 'i/o error\\|ata'"
echo
echo "Host drill-down:"
echo "  ./use-practice status"
echo "  pidstat -d 1"
echo "  iotop -bn1"
print_host_footer
