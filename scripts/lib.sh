#!/usr/bin/env bash

USE_PRACTICE_ROOT="${USE_PRACTICE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BIN_DIR="${BIN_DIR:-$USE_PRACTICE_ROOT/bin}"

SCENARIOS=(cpu memory disk network)
SERVICE_POOL=(
  api worker cache queue auth billing search checkout ingest gateway
  notifications reports scheduler catalog profiles payments fraud session
  orders inventory shipping telemetry events jobs recommender indexer
)
SERVICES=()

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required for this scenario."
}

require_workload_bin() {
  local bin="$1"
  [ -x "$BIN_DIR/$bin" ] || \
    die "workload binary '$bin' not found in $BIN_DIR (run scripts/build.sh)."
}

# stage_workload <binary> <service>
#
# Copies the workload binary to a per-run, service-named path and writes its
# config (read from stdin) alongside it. The running process then shows up only
# as the service name in ps/top with no arguments, and the binary reads its
# parameters from the adjacent <service>.cfg file (which it unlinks on start).
# Echoes the staged binary path for the caller to launch.
stage_workload() {
  local binary="$1"
  local service="$2"
  local dir="$RUNTIME_DIR/bin"
  mkdir -p "$dir"
  cp "$BIN_DIR/$binary" "$dir/$service"
  chmod 755 "$dir/$service"
  cat > "$dir/$service.cfg"
  echo "$dir/$service"
}

is_scenario() {
  local wanted="${1:-}"
  local scenario
  for scenario in "${SCENARIOS[@]}"; do
    if [ "$scenario" = "$wanted" ]; then
      return 0
    fi
  done
  return 1
}

pick_random_scenario() {
  echo "${SCENARIOS[$((RANDOM % ${#SCENARIOS[@]}))]}"
}

new_run_id() {
  printf 'r%04x%04x' "$RANDOM" "$RANDOM"
}

choose_services() {
  local count="${1:-$((3 + RANDOM % 3))}"
  local picked=()
  local candidate exists item

  while [ "${#picked[@]}" -lt "$count" ]; do
    candidate="${SERVICE_POOL[$((RANDOM % ${#SERVICE_POOL[@]}))]}"
    exists=0
    for item in "${picked[@]}"; do
      if [ "$item" = "$candidate" ]; then
        exists=1
        break
      fi
    done
    if [ "$exists" -eq 0 ]; then
      picked+=("$candidate")
    fi
  done

  SERVICES=("${picked[@]}")
}

pick_random_service() {
  if [ "${#SERVICES[@]}" -eq 0 ]; then
    choose_services
  fi
  echo "${SERVICES[$((RANDOM % ${#SERVICES[@]}))]}"
}

start_run() {
  RUN_ID="${RUN_ID:-$(new_run_id)}"
  WORKLOAD_PREFIX="${WORKLOAD_PREFIX:-up-$RUN_ID}"
  RUNTIME_DIR="${RUNTIME_DIR:-$PWD/.runtime}"
  LOG_DIR="${LOG_DIR:-$PWD/.logs}"
  choose_services "${1:-}"
  mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
}

start_service() {
  local name="$1"
  local summary="$2"
  local script="$3"
  local logfile="$LOG_DIR/$name.log"
  local pid

  mkdir -p "$LOG_DIR"
  if command -v setsid >/dev/null 2>&1; then
    nohup setsid env \
      USE_PRACTICE_RUN_ID="$RUN_ID" \
      USE_PRACTICE_SERVICE="$name" \
      bash -c 'exec -a "$0" bash -c "$1" "$0"' "$name" "$script" >"$logfile" 2>&1 </dev/null &
  else
    nohup env \
      USE_PRACTICE_RUN_ID="$RUN_ID" \
      USE_PRACTICE_SERVICE="$name" \
      bash -c 'exec -a "$0" bash -c "$1" "$0"' "$name" "$script" >"$logfile" 2>&1 </dev/null &
  fi
  pid="$!"
  disown "$pid" >/dev/null 2>&1 || true
  echo "$pid" >> .pids
  printf '%s\t%s\t%s\t%s\n' "$pid" "$name" "$summary" "$logfile" >> .processes
}

stop_recorded_processes() {
  local pids=()
  local pid i

  if [ ! -f .pids ]; then
    return 0
  fi

  mapfile -t pids < .pids
  for ((i=${#pids[@]} - 1; i >= 0; i--)); do
    pid="${pids[$i]}"
    [ -n "$pid" ] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM -- "-$pid" >/dev/null 2>&1 || kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  done

  sleep 1

  for ((i=${#pids[@]} - 1; i >= 0; i--)); do
    pid="${pids[$i]}"
    [ -n "$pid" ] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  done
}

setup_veth_pair() {
  local suffix="${RUN_ID#r}"
  suffix="${suffix:0:8}"
  NETNS="up-${suffix}"
  VETH_HOST="veth${suffix}h"
  VETH_PEER="veth${suffix}p"
  VETH_HOST_IP="10.231.0.1"
  VETH_PEER_IP="10.231.0.2"

  local ip_cmd=(ip)
  if [ "$(id -u)" != "0" ]; then
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true >/dev/null 2>&1 || return 1
    ip_cmd=(sudo ip)
  fi
  command -v ip >/dev/null 2>&1 || return 1

  if ! "${ip_cmd[@]}" netns add "$NETNS" >/dev/null 2>&1; then
    return 1
  fi
  if ! "${ip_cmd[@]}" link add "$VETH_HOST" type veth peer name "$VETH_PEER" >/dev/null 2>&1; then
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" addr add "$VETH_HOST_IP/30" dev "$VETH_HOST" >/dev/null 2>&1; then
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" link set "$VETH_HOST" up >/dev/null 2>&1; then
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" link set "$VETH_PEER" netns "$NETNS" >/dev/null 2>&1; then
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" netns exec "$NETNS" ip addr add "$VETH_PEER_IP/30" dev "$VETH_PEER" >/dev/null 2>&1; then
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" netns exec "$NETNS" ip link set lo up >/dev/null 2>&1; then
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "${ip_cmd[@]}" netns exec "$NETNS" ip link set "$VETH_PEER" up >/dev/null 2>&1; then
    "${ip_cmd[@]}" netns delete "$NETNS" >/dev/null 2>&1 || true
    "${ip_cmd[@]}" link delete "$VETH_HOST" >/dev/null 2>&1 || true
    return 1
  fi

  echo "$NETNS" > .netns
  echo "$VETH_HOST" > .links
  return 0
}

cleanup_network_state() {
  local item
  local ip_cmd=(ip)
  if [ "$(id -u)" != "0" ]; then
    command -v sudo >/dev/null 2>&1 || return 0
    sudo -n true >/dev/null 2>&1 || return 0
    ip_cmd=(sudo ip)
  fi
  if command -v ip >/dev/null 2>&1; then
    if [ -f .netns ]; then
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        "${ip_cmd[@]}" netns delete "$item" >/dev/null 2>&1 || true
      done < .netns
    fi
    if [ -f .links ]; then
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        "${ip_cmd[@]}" link delete "$item" >/dev/null 2>&1 || true
      done < .links
    fi
  fi
}

delete_scenario_resources() {
  stop_recorded_processes
  cleanup_network_state
  rm -rf .runtime .logs
  rm -f \
    .env .answer .run-id .pids .processes .netns .links \
    .plan.sh .rendered.yaml .rendered-body.yaml .rendered-role.yaml
}

print_recorded_processes() {
  local file="$1"
  local pid name summary logfile

  if [ ! -f "$file" ]; then
    echo "No recorded workload processes."
    return 0
  fi

  printf '%-8s %-18s %-10s %s\n' "PID" "SERVICE" "STATE" "COMMAND"
  while IFS=$'\t' read -r pid name summary logfile; do
    [ -n "$pid" ] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      printf '%-8s %-18s %-10s %s\n' "$pid" "$name" "running" "$summary"
    else
      printf '%-8s %-18s %-10s %s\n' "$pid" "$name" "exited" "$summary"
      if [ -n "${logfile:-}" ] && [ -f "$logfile" ]; then
        echo "  log: $logfile"
      fi
    fi
  done < "$file"
}

print_host_footer() {
  cat <<EOF

Status: ./use-practice status
Stop:   ./stop.sh
Reveal: ./reveal.sh
EOF
}
