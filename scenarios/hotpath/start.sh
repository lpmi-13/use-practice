#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

PYTHON="$(python_cmd)"

ENDPOINTS=(search report aggregate export)
SIZES=(500 600 700 800)

start_run 2
CULPRIT="${SERVICES[0]}"
LOAD_DRIVER="${SERVICES[1]}"
HOT_ENDPOINT="${ENDPOINTS[$((RANDOM % ${#ENDPOINTS[@]}))]}"
HOT_SIZE="${SIZES[$((RANDOM % ${#SIZES[@]}))]}"
RPS_PER_TARGET=$((30 + RANDOM % 30))
PORT=$((18000 + RANDOM % 1000))

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
LOAD_DRIVER=$LOAD_DRIVER
HOT_ENDPOINT=$HOT_ENDPOINT
HOT_SIZE=$HOT_SIZE
RPS_PER_TARGET=$RPS_PER_TARGET
PORT=$PORT
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:    CPU (hot code path)
Service:     $CULPRIT
Endpoint:    /$HOT_ENDPOINT
Function:    handle_$HOT_ENDPOINT() in scenarios/hotpath/app/server.py
Loop:        nested for-loop, N=$HOT_SIZE  (so N*N = $((HOT_SIZE * HOT_SIZE)) iters per request)
Load:        $RPS_PER_TARGET req/s from $LOAD_DRIVER
Load driver: $LOAD_DRIVER
Port:        $PORT
Run ID:      $RUN_ID
EOF

SERVER_SCRIPT=$(cat <<EOF
SERVICE_NAME="$CULPRIT" \
CULPRIT="$CULPRIT" \
HOT_ENDPOINT="$HOT_ENDPOINT" \
HOT_SIZE="$HOT_SIZE" \
PORT="$PORT" \
exec -a "\$0" "$PYTHON" app/server.py
EOF
)

start_service \
  "$CULPRIT" \
  "$PYTHON app/server.py -- port $PORT" \
  "$SERVER_SCRIPT"

sleep 1

LOAD_SCRIPT=$(cat <<EOF
TARGETS="127.0.0.1" \
TARGET_PORT="$PORT" \
RPS_PER_TARGET="$RPS_PER_TARGET" \
exec -a "\$0" "$PYTHON" app/loadgen.py
EOF
)

start_service \
  "$LOAD_DRIVER" \
  "$PYTHON app/loadgen.py -> 127.0.0.1:$PORT" \
  "$LOAD_SCRIPT"

echo "Hotpath scenario running. Service '$CULPRIT' is a local Python HTTP service."
echo "One endpoint has a nested for-loop and is under load from '$LOAD_DRIVER'."
echo
echo "USE method starting points:"
echo "  Utilization: top -bcn1 w512"
echo "  Saturation:  vmstat 1             (run-queue 'r' on a busy host)"
echo
echo "Profiler drill-down:"
echo "  ./use-practice status"
echo "  py-spy top --pid <service-pid>"
echo "  py-spy dump --pid <service-pid>"
echo
echo "The hot function name (handle_<endpoint>) tells you which route is slow."
print_host_footer
