#!/usr/bin/env bash
# Runs inside the iximiuz VM. Use scripts/smoke-iximiuz-live.sh from the local
# repo to copy and execute this script through labctl.
set -euo pipefail

root="${USE_PRACTICE_ROOT:-/opt/use-practice}"
require_network_veth="${REQUIRE_NETWORK_VETH:-1}"
wait_lab_ready="${WAIT_LAB_READY:-1}"
run_cpu_kernelwait="${RUN_CPU_KERNELWAIT:-1}"
run_disk_saturation="${RUN_DISK_SATURATION:-1}"
run_network_highload="${RUN_NETWORK_HIGHLOAD:-1}"
run_memory_oom="${RUN_MEMORY_OOM:-1}"

cd "$root"

cleanup() {
  ./use-practice stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

log() {
  printf '\n== %s ==\n' "$*"
}

need_file() {
  local path="$1"
  [ -e "$path" ] || {
    echo "missing expected path: $path" >&2
    exit 1
  }
}

need_executable() {
  local path="$1"
  [ -x "$path" ] || {
    echo "missing executable: $path" >&2
    exit 1
  }
}

need_absent() {
  local path="$1"
  [ ! -e "$path" ] || {
    echo "unexpected removed wrapper still present: $path" >&2
    exit 1
  }
}

need_pattern() {
  local pattern="$1"
  local path="$2"
  if ! grep -Eq "$pattern" "$path"; then
    echo "expected pattern '$pattern' in $path" >&2
    cat "$path" >&2 || true
    exit 1
  fi
}

run_tty() {
  local keys="$1"
  shift
  command -v script >/dev/null 2>&1 || {
    echo "script(1) is required for selector smoke tests" >&2
    exit 1
  }
  printf '%b' "$keys" | script -qfec "$*" /dev/null
}

wait_ready() {
  local timeout_seconds="${USE_PRACTICE_READY_TIMEOUT_SECONDS:-240}"
  local deadline=$((SECONDS + timeout_seconds))

  while [ "$SECONDS" -lt "$deadline" ]; do
    [ -f /var/lib/use-practice/ready ] && return 0
    sleep 2
  done

  echo "use-practice lab did not become ready within ${timeout_seconds}s" >&2
  systemctl status use-practice-bootstrap.service --no-pager >&2 || true
  return 1
}

log "readiness"
if [ "$wait_lab_ready" != "0" ]; then
  wait_ready
fi

for path in \
  ./use-practice \
  /usr/local/bin/use-practice \
  ./bin/uworker \
  ./bin/updisk \
  ./bin/uwait
do
  need_executable "$path"
done

for path in \
  ./use-practice.sh \
  ./run.sh \
  ./reveal.sh \
  ./stop-all.sh \
  scenarios/cpu/reveal.sh \
  scenarios/memory/reveal.sh \
  scenarios/disk/reveal.sh \
  scenarios/network/reveal.sh \
  scripts/wait-lab-ready.sh \
  scripts/push-images.sh \
  scripts/test-status-output.sh \
  scripts/update-version-refs.sh \
  scripts/lib/versions.sh \
  scripts/build.sh \
  scripts/build-rootfs-image.sh \
  scripts/smoke-iximiuz-live.sh \
  scripts/iximiuz-live-smoke-remote.sh \
  /opt/iximiuz-labs/bootstrap-use-practice.sh
do
  need_absent "$path"
done

for path in \
  scenarios/cpu/start.sh \
  scenarios/memory/start.sh \
  scenarios/disk/start.sh \
  scenarios/network/start.sh
do
  need_file "$path"
done

log "safe cli checks"
./use-practice list | grep -q '^network'
./use-practice status | grep -q '^No active scenario\.$'
run_tty '4\n' './use-practice' | grep -q '^network'

if [ "$run_cpu_kernelwait" != "0" ]; then
  log "cpu kernelwait"
  run_tty '4\n' './use-practice run cpu'
  need_pattern '^PROFILE=kernelwait$' scenarios/cpu/.env
  ./use-practice status | grep -q '^Active run: '
  ./use-practice stop
fi

if [ "$run_disk_saturation" != "0" ]; then
  log "disk saturation"
  run_tty '3\n' './use-practice run disk'
  need_pattern '^PROFILE=saturation$' scenarios/disk/.env
  ./use-practice status | grep -q '^Active run: '
  ./use-practice stop
fi

if [ "$run_network_highload" != "0" ]; then
  log "network highload"
  run_tty '4\n' './use-practice run network'
  need_pattern '^PROFILE=highload$' scenarios/network/.env
  if [ "$require_network_veth" != "0" ]; then
    if grep -q '^NETWORK_PATH=loopback fallback$' scenarios/network/.env; then
      echo "network scenario used loopback fallback; expected veth/netns in iximiuz" >&2
      cat scenarios/network/.env >&2
      exit 1
    fi
  fi
  ./use-practice status | grep -q '^Active run: '
  ./use-practice stop
fi

if [ "$run_memory_oom" != "0" ]; then
  log "memory oom"
  run_tty '4\n' './use-practice run memory'
  need_pattern '^PROFILE=oom$' scenarios/memory/.env
  cg="$(awk -F= '/^CGROUP_DIR=/ {print $2}' scenarios/memory/.env)"
  [ -n "$cg" ] || {
    echo "memory OOM scenario did not record CGROUP_DIR" >&2
    cat scenarios/memory/.env >&2
    exit 1
  }

  oom_kill=0
  for _ in $(seq 1 45); do
    if [ -f "$cg/memory.events" ]; then
      oom_kill="$(awk '/^oom_kill / {print $2}' "$cg/memory.events")"
      oom_kill="${oom_kill:-0}"
      if [ "$oom_kill" -gt 0 ]; then
        break
      fi
    fi
    sleep 1
  done

  if [ "$oom_kill" -le 0 ]; then
    echo "memory.events oom_kill did not increase" >&2
    [ -f "$cg/memory.events" ] && cat "$cg/memory.events" >&2
    exit 1
  fi
  ./use-practice status | grep -q '^Active run: '
  ./use-practice stop
fi

log "post-cleanup"
./use-practice status | grep -q '^No active scenario\.$'

echo
echo "iximiuz live smoke passed"
