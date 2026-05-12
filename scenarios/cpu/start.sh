#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(api worker cache queue auth)
CULPRIT="${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
WORKERS=$((1 + RANDOM % 4))

cat > .env <<EOF
CULPRIT=$CULPRIT
WORKERS=$WORKERS
EOF

cat > .answer <<EOF
Resource:  CPU
Culprit:   $CULPRIT
Workers:   $WORKERS
Process:   stress-ng --cpu $WORKERS --cpu-method matrixprod
EOF

docker compose up -d --build >/dev/null
echo "CPU scenario running. 5 services are up; one is hammering the CPU."
echo
echo "USE method starting points:"
echo "  Utilization: top / htop / mpstat -P ALL 1"
echo "  Saturation:  vmstat 1   (look at 'r' run-queue column)"
echo "  Errors:      perf / dmesg (rare on CPU)"
echo
echo "Per-container view:"
echo "  docker stats"
echo "  docker exec <name> top -bn1"
echo
echo "Stop:   ./stop.sh    Reveal: ./reveal.sh"
