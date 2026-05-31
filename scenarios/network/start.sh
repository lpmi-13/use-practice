#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

require_workload_bin uworker

start_run "$((5 + RANDOM % 6))"
CULPRIT="${SERVICES[0]}"
TARGET_SERVICE="${SERVICES[1]}"
SINK_PORT=$((5200 + RANDOM % 100))
BW_MBPS=$((100 + RANDOM % 400))
PARALLEL=$((1 + RANDOM % 4))
PROTO_OPTIONS=(tcp udp)
NETWORK_PROTO="${PROTO_OPTIONS[$((RANDOM % ${#PROTO_OPTIONS[@]}))]}"
if [ "$NETWORK_PROTO" = "udp" ]; then
  NETWORK_SIGNAL="UDP loss/jitter and interface drops under offered load"
else
  NETWORK_SIGNAL="TCP throughput, retransmits, and socket queue pressure"
fi

# Stage the sink (server). It may need to run inside a netns, so it is launched
# directly rather than through launch_workload.
SERVER_BIN="$(stage_workload uworker "$TARGET_SERVICE" <<EOF
mode=netserver
proto=$NETWORK_PROTO
port=$SINK_PORT
EOF
)"

if setup_veth_pair; then
  TARGET_HOST="$VETH_PEER_IP"
  NETWORK_PATH="$VETH_HOST on the host to $VETH_PEER in netns $NETNS"
  if [ "$(id -u)" = "0" ]; then
    SERVER_SCRIPT="exec -a \"\$0\" ip netns exec \"$NETNS\" \"$SERVER_BIN\""
  else
    SERVER_SCRIPT="exec -a \"\$0\" sudo -n ip netns exec \"$NETNS\" \"$SERVER_BIN\""
  fi
  NETWORK_NOTE="Traffic should be visible on host interface $VETH_HOST."
else
  TARGET_HOST="127.0.0.1"
  NETWORK_PATH="loopback fallback"
  SERVER_SCRIPT="exec -a \"\$0\" \"$SERVER_BIN\""
  NETWORK_NOTE="Traffic is on loopback because veth/netns setup was unavailable; include lo in interface checks."
fi

cat > .env <<EOF
RUN_ID=$RUN_ID
CULPRIT=$CULPRIT
TARGET_SERVICE=$TARGET_SERVICE
TARGET_HOST=$TARGET_HOST
TARGET_PORT=$SINK_PORT
BW_MBPS=$BW_MBPS
PARALLEL=$PARALLEL
NETWORK_PROTO=$NETWORK_PROTO
NETWORK_PATH=$NETWORK_PATH
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Network
Service:   $CULPRIT
Target:    $TARGET_SERVICE at $TARGET_HOST:$SINK_PORT
Path:      $NETWORK_PATH
Protocol:  $NETWORK_PROTO
Bandwidth: ${BW_MBPS} Mbit/s offered
Streams:   $PARALLEL parallel flows
Signal:    $NETWORK_SIGNAL
Fleet:     ${SERVICES[*]}
Process:   in-tree network source '$CULPRIT' -> sink '$TARGET_SERVICE'
           The other services are baseline decoys (tiny loopback chatter).
Run ID:    $RUN_ID
EOF

start_service \
  "$TARGET_SERVICE" \
  "network sink on :$SINK_PORT ($NETWORK_PROTO)" \
  "$SERVER_SCRIPT"

sleep 1

launch_workload uworker "$CULPRIT" "network source -> $TARGET_HOST:$SINK_PORT (${BW_MBPS}M x$PARALLEL)" <<EOF
mode=netclient
proto=$NETWORK_PROTO
host=$TARGET_HOST
port=$SINK_PORT
mbps=$BW_MBPS
parallel=$PARALLEL
EOF

launch_baseline_fleet uworker "$CULPRIT" "$TARGET_SERVICE"

echo "Network scenario running. ${#SERVICES[@]} services are up; one is generating sustained traffic."
echo "$NETWORK_NOTE"
echo
echo "USE method starting points:"
echo "  Utilization: sar -n DEV 1   (rxkB/s, txkB/s vs link speed)"
echo "  Saturation:  ss -s, ss -tin (retrans, cwnd)"
echo "  Errors:      ip -s link, sar -n EDEV 1   (drops, errors)"
echo
echo "Host drill-down (find the heavy talker):"
echo "  ./use-practice status"
echo "  ss -tnp"
echo "  ip -s link"
print_host_footer
