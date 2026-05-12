#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(api worker cache queue auth)
CULPRIT="${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
# 300-800 MB resident
MEM_MB=$((300 + RANDOM % 500))

cat > .env <<EOF
CULPRIT=$CULPRIT
MEM_MB=$MEM_MB
EOF

cat > .answer <<EOF
Resource:  Memory
Culprit:   $CULPRIT
Resident:  ${MEM_MB} MB
Process:   stress-ng --vm 1 --vm-bytes ${MEM_MB}m --vm-keep
EOF

docker compose up -d --build >/dev/null
echo "Memory scenario running. One service is sitting on a large resident set."
echo
echo "USE method starting points:"
echo "  Utilization: free -m   (look at used/available)"
echo "  Saturation:  vmstat 1  (si/so swap columns), /proc/pressure/memory"
echo "  Errors:      dmesg | grep -i 'killed process\\|oom'"
echo
echo "Per-container view:"
echo "  docker stats --no-stream --format 'table {{.Name}}\\t{{.MemUsage}}\\t{{.MemPerc}}'"
echo
echo "Stop:   ./stop.sh    Reveal: ./reveal.sh"
