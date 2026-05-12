#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SCENARIOS=(cpu memory disk network)
MODE="${1:-random}"

usage() {
  cat <<EOF
Usage: $0 [cpu|memory|disk|network|random]

  cpu|memory|disk|network   Run that specific scenario (verbose)
  random (default)          Pick one at random and DON'T tell you which.
                            Use the USE method to figure it out.
EOF
}

pick_random() {
  echo "${SCENARIOS[$((RANDOM % ${#SCENARIOS[@]}))]}"
}

case "$MODE" in
  -h|--help) usage; exit 0 ;;
  cpu|memory|disk|network|random) ;;
  *) usage; exit 1 ;;
esac

if [ "$MODE" = "random" ]; then
  PICK="$(pick_random)"
else
  PICK="$MODE"
fi

if [ -f .active-scenario ]; then
  prev=$(cat .active-scenario)
  if [ -d "scenarios/$prev" ] && [ "$prev" != "$PICK" ]; then
    (cd "scenarios/$prev" && ./stop.sh) || true
  fi
fi
echo "$PICK" > .active-scenario

if [ "$MODE" = "random" ]; then
  # Blind mode: hide the scenario's own banner so the user has to diagnose.
  ( cd "scenarios/$PICK" && ./start.sh >/dev/null )
  cat <<'EOF'
==> Blind scenario started. The resource type is hidden.

Walk the USE method across every resource:
  CPU:     top  /  vmstat 1  /  mpstat -P ALL 1
  Memory:  free -m  /  vmstat 1 (si/so)  /  dmesg | grep -i oom
  Disk:    iostat -xz 1  /  pidstat -d 1
  Network: sar -n DEV 1  /  ss -s  /  ip -s link

Per-container view:
  docker stats
  docker exec <name> top -bn1

When you have an answer:
  ./reveal.sh        # prints what was actually wrong
  ./stop-all.sh      # tear everything down
EOF
else
  echo "==> Running scenario: $PICK"
  exec "scenarios/$PICK/start.sh"
fi
