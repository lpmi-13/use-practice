#!/usr/bin/env bash
set -euo pipefail

state_dir="/var/lib/use-practice"
ready_marker="${state_dir}/ready"

mkdir -p "${state_dir}"

if id laborant >/dev/null 2>&1; then
  chown -R laborant:laborant /opt/use-practice
  ln -sfn /opt/use-practice /home/laborant/use-practice
  chown -h laborant:laborant /home/laborant/use-practice
fi

for cmd in fio iperf3 iostat mpstat pidstat py-spy sar stress-ng use-practice use-tool; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "missing expected tool: ${cmd}" >&2
    exit 1
  }
done

touch "${ready_marker}"
chmod 0644 "${ready_marker}"
