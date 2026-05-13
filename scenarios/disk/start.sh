#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(api worker cache queue auth)
CULPRIT="${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
BS_OPTIONS=(4 16 64 256)
BS_K=${BS_OPTIONS[$((RANDOM % ${#BS_OPTIONS[@]}))]}
IODEPTH=$((8 + RANDOM % 25))
RW_OPTIONS=(randwrite randread randrw)
RW=${RW_OPTIONS[$((RANDOM % ${#RW_OPTIONS[@]}))]}
FIO_FILE_SIZE=256M

cat > .env <<EOF
CULPRIT=$CULPRIT
BS_K=$BS_K
IODEPTH=$IODEPTH
RW=$RW
FIO_FILE_SIZE=$FIO_FILE_SIZE
EOF

cat > .answer <<EOF
Resource:  Disk
Culprit:   $CULPRIT
Pattern:   $RW
Block:     ${BS_K}k
IO depth:  $IODEPTH
File size: $FIO_FILE_SIZE
Process:   fio (direct=1, libaio)
EOF

docker compose up -d --build >/dev/null
echo "Disk scenario running. One service is hammering /data via fio."
echo "Disk footprint is bounded to one ${FIO_FILE_SIZE} file in the Docker volume."
echo
echo "USE method starting points:"
echo "  Utilization: iostat -xz 1   (look at %util column)"
echo "  Saturation:  iostat -xz 1   (aqu-sz / await rising)"
echo "  Errors:      dmesg | grep -i 'i/o error\\|ata'"
echo
echo "Per-container view:"
echo "  docker stats --no-stream --format 'table {{.Name}}\\t{{.BlockIO}}'"
echo "  docker exec <name> sh -c 'cat /proc/1/io 2>/dev/null'"
echo
echo "Stop:   ./stop.sh    Reveal: ./reveal.sh"
