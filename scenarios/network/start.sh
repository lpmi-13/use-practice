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
PROFILE_OPTIONS=(utilization saturation highload)
PROFILE="${NETWORK_PROFILE:-random}"
case "$PROFILE" in
  random) PROFILE="${PROFILE_OPTIONS[$((RANDOM % ${#PROFILE_OPTIONS[@]}))]}" ;;
  utilization|saturation|highload) ;;
  *) die "NETWORK_PROFILE must be 'utilization', 'saturation', 'highload', or 'random'." ;;
esac

SERVER_READ_BPS=0
SERVER_READ_BUF=0
CLIENT_WRITE_BUF=0
if [ "$PROFILE" = "utilization" ]; then
  NETWORK_PROTO=tcp
  BW_MBPS=$((600 + RANDOM % 401))
  PARALLEL=$((2 + RANDOM % 3))
  PROFILE_LABEL="Utilization: steady high-throughput TCP transfer"
  NETWORK_SIGNAL="High interface throughput with a draining sink; socket queues should stay comparatively quiet."
  SINK_LINE="Sink:      draining"
elif [ "$PROFILE" = "saturation" ]; then
  NETWORK_PROTO=tcp
  BW_MBPS=$((40 + RANDOM % 41))
  PARALLEL=1
  READ_MBPS=$((1 + RANDOM % 3))
  SERVER_READ_BPS=$((READ_MBPS * 1000 * 1000 / 8))
  SERVER_READ_BUF=4096
  CLIENT_WRITE_BUF=32768
  PROFILE_LABEL="Saturation: slow receiver / TCP backpressure"
  NETWORK_SIGNAL="Low actual throughput with TCP Send-Q or sndbuf/rwnd-limited evidence from the blocked sender."
  SINK_LINE="Sink cap:  ${READ_MBPS} Mbit/s"
else
  BW_MBPS=$((100 + RANDOM % 400))
  PARALLEL=$((1 + RANDOM % 4))
  PROTO_OPTIONS=(tcp udp)
  NETWORK_PROTO="${PROTO_OPTIONS[$((RANDOM % ${#PROTO_OPTIONS[@]}))]}"
  PROFILE_LABEL="High load: offered traffic can drive utilization and saturation together"
  SINK_LINE="Sink:      draining"
  if [ "$NETWORK_PROTO" = "udp" ]; then
    NETWORK_SIGNAL="UDP loss/jitter and interface drops under offered load"
  else
    NETWORK_SIGNAL="TCP throughput, retransmits, and socket queue pressure"
  fi
fi

# Stage the sink (server). It may need to run inside a netns, so it is launched
# directly rather than through launch_workload.
SERVER_BIN="$(stage_workload uworker "$TARGET_SERVICE" <<EOF
mode=netserver
proto=$NETWORK_PROTO
port=$SINK_PORT
read_bps=$SERVER_READ_BPS
read_buf=$SERVER_READ_BUF
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
PROFILE=$PROFILE
TARGET_SERVICE=$TARGET_SERVICE
TARGET_HOST=$TARGET_HOST
TARGET_PORT=$SINK_PORT
BW_MBPS=$BW_MBPS
PARALLEL=$PARALLEL
NETWORK_PROTO=$NETWORK_PROTO
NETWORK_PATH=$NETWORK_PATH
SERVER_READ_BPS=$SERVER_READ_BPS
SERVER_READ_BUF=$SERVER_READ_BUF
CLIENT_WRITE_BUF=$CLIENT_WRITE_BUF
SERVICES=${SERVICES[*]}
EOF
echo "$RUN_ID" > .run-id

cat > .answer <<EOF
Resource:  Network
Service:   $CULPRIT
Profile:   $PROFILE_LABEL
Target:    $TARGET_SERVICE at $TARGET_HOST:$SINK_PORT
Path:      $NETWORK_PATH
Protocol:  $NETWORK_PROTO
Bandwidth: ${BW_MBPS} Mbit/s offered
Streams:   $PARALLEL parallel flows
$SINK_LINE
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
write_buf=$CLIENT_WRITE_BUF
EOF

launch_baseline_fleet uworker "$CULPRIT" "$TARGET_SERVICE"

echo "Network scenario running. ${#SERVICES[@]} services are up; one is generating sustained traffic."
echo "$NETWORK_NOTE"
echo
echo "USE method starting points:"
echo "  Utilization: sar -n DEV 1   (rxkB/s, txkB/s vs link speed)"
echo "  Saturation:  ss -s, ss -tin (Send-Q, retrans, rwnd/sndbuf-limited)"
echo "  Errors:      ip -s link, sar -n EDEV 1   (drops, errors)"
echo
echo "Host drill-down (find the heavy talker):"
echo "  ./use-practice status"
echo "  ss -tnp"
echo "  ip -s link"
print_host_footer
