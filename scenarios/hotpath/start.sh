#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(api worker cache queue auth)
ENDPOINTS=(search report aggregate export)
SIZES=(500 600 700 800)

CULPRIT="${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
HOT_ENDPOINT="${ENDPOINTS[$((RANDOM % ${#ENDPOINTS[@]}))]}"
HOT_SIZE="${SIZES[$((RANDOM % ${#SIZES[@]}))]}"
RPS_PER_TARGET=$((30 + RANDOM % 30))

cat > .env <<EOF
CULPRIT=$CULPRIT
HOT_ENDPOINT=$HOT_ENDPOINT
HOT_SIZE=$HOT_SIZE
RPS_PER_TARGET=$RPS_PER_TARGET
EOF

cat > .answer <<EOF
Resource:    CPU (hot code path)
Culprit:     $CULPRIT
Endpoint:    /$HOT_ENDPOINT
Function:    handle_$HOT_ENDPOINT() in /app/server.py
Loop:        nested for-loop, N=$HOT_SIZE  (so N*N = $((HOT_SIZE * HOT_SIZE)) iters per request)
Load:        $RPS_PER_TARGET req/s per service from the 'loadgen' container
EOF

docker compose up -d --build >/dev/null
echo "Hotpath scenario running. 5 services + 1 loadgen are up."
echo "One service has a nested for-loop on one endpoint."
echo
echo "USE method starting points:"
echo "  Utilization: top / docker stats   (one container hot, rest light)"
echo "  Saturation:  vmstat 1             (run-queue 'r' on a busy host)"
echo
echo "Drill into the hot container with a profiler:"
echo "  PID=\$(docker exec <name> pgrep -f server.py)"
echo "  docker exec <name> py-spy top --pid \$PID"
echo "  docker exec <name> py-spy dump --pid \$PID    # full stacks"
echo
echo "The hot function name (handle_<endpoint>) tells you which route is slow."
echo
echo "Stop:   ./stop.sh    Reveal: ./reveal.sh"
