#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../../scripts/lib.sh
source ../../scripts/lib.sh

need_cmd iperf3

start_run 2
CULPRIT="${SERVICES[0]}"
TARGET_SERVICE="${SERVICES[1]}"
SINK_PORT=$((5200 + RANDOM % 100))
BW_MBPS=$((100 + RANDOM % 400))
PARALLEL=$((1 + RANDOM % 4))
PROTO_OPTIONS=(tcp udp)
NETWORK_PROTO="${PROTO_OPTIONS[$((RANDOM % ${#PROTO_OPTIONS[@]}))]}"
if [ "$NETWORK_PROTO" = "udp" ]; then
  IPERF_MODE="-u"
  NETWORK_SIGNAL="UDP loss/jitter and interface drops under offered load"
else
  IPERF_MODE=""
  NETWORK_SIGNAL="TCP throughput, retransmits, and socket queue pressure"
fi

if setup_veth_pair; then
  TARGET_HOST="$VETH_PEER_IP"
  NETWORK_PATH="$VETH_HOST on the host to $VETH_PEER in netns $NETNS"
  if [ "$(id -u)" = "0" ]; then
    SERVER_SCRIPT="exec -a \"\$0\" ip netns exec \"$NETNS\" iperf3 -s -p \"$SINK_PORT\""
  else
    SERVER_SCRIPT="exec -a \"\$0\" sudo -n ip netns exec \"$NETNS\" iperf3 -s -p \"$SINK_PORT\""
  fi
  NETWORK_NOTE="Traffic should be visible on host interface $VETH_HOST."
else
  TARGET_HOST="127.0.0.1"
  NETWORK_PATH="loopback fallback"
  SERVER_SCRIPT="exec -a \"\$0\" iperf3 -s -p \"$SINK_PORT\""
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
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Network
Service:   $CULPRIT
Target:    $TARGET_SERVICE at $TARGET_HOST:$SINK_PORT
Path:      $NETWORK_PATH
Protocol:  $NETWORK_PROTO
Bandwidth: ${BW_MBPS} Mbit/s offered
Streams:   $PARALLEL parallel iperf3 flows
Signal:    $NETWORK_SIGNAL
Run ID:    $RUN_ID
EOF

start_service \
  "$TARGET_SERVICE" \
  "iperf3 -s -p $SINK_PORT" \
  "$SERVER_SCRIPT"

sleep 1

CLIENT_SCRIPT=$(cat <<EOF
while true; do
  iperf3 $IPERF_MODE -c "$TARGET_HOST" -p "$SINK_PORT" -t 60 -b "${BW_MBPS}M" -P "$PARALLEL" >/dev/null 2>&1 || sleep 1
done
EOF
)

start_service \
  "$CULPRIT" \
  "iperf3 $NETWORK_PROTO client to $TARGET_HOST:$SINK_PORT" \
  "$CLIENT_SCRIPT"

echo "Network scenario running. Service '$CULPRIT' is generating sustained traffic."
echo "$NETWORK_NOTE"
echo
echo "USE method starting points:"
echo "  Utilization: sar -n DEV 1   (rxkB/s, txkB/s vs link speed)"
echo "  Saturation:  ss -s, ss -tin (retrans, cwnd)"
echo "  Errors:      ip -s link, sar -n EDEV 1   (drops, errors)"
echo
echo "Host drill-down:"
echo "  ./use-practice status"
echo "  ss -tnp | grep iperf3"
echo "  ip -s link"
print_host_footer
