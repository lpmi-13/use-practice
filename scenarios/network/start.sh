#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(api worker cache queue auth)
CULPRIT="${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
SINK_PORT=$((5200 + RANDOM % 100))
BW_MBPS=$((200 + RANDOM % 800))
PARALLEL=$((1 + RANDOM % 4))

cat > .env <<EOF
CULPRIT=$CULPRIT
SINK_PORT=$SINK_PORT
BW_MBPS=$BW_MBPS
PARALLEL=$PARALLEL
EOF

cat > .answer <<EOF
Resource:  Network
Culprit:   $CULPRIT
Target:    sink:${SINK_PORT}
Bandwidth: ${BW_MBPS} Mbit/s offered
Streams:   $PARALLEL parallel iperf3 flows
EOF

docker compose up -d --build >/dev/null
echo "Network scenario running. One service is flooding traffic to 'sink'."
echo
echo "USE method starting points:"
echo "  Utilization: sar -n DEV 1   (rxkB/s, txkB/s vs link speed)"
echo "  Saturation:  ss -s, ss -tin (retrans, cwnd)"
echo "  Errors:      ip -s link, sar -n EDEV 1   (drops, errors)"
echo
echo "Per-container view:"
echo "  docker stats --no-stream --format 'table {{.Name}}\\t{{.NetIO}}'"
echo "  docker exec <name> ip -s link show eth0"
echo
echo "Stop:   ./stop.sh    Reveal: ./reveal.sh"
