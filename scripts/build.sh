#!/usr/bin/env bash
# Build the workload binaries into ./bin. The iximiuz image builds these the
# same way in a multi-stage Docker build; this script is for local runs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$root/bin"
mkdir -p "$bin"

echo "building Go workloads (upcpu, upmem, upnet)..."
(
  cd "$root/loadgen/go"
  for cmd in upcpu upmem upnet; do
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$bin/$cmd" "./cmd/$cmd"
  done
)

echo "building Rust disk workload (updisk)..."
(
  cd "$root/loadgen/rust/updisk"
  cargo build --release --offline 2>/dev/null || cargo build --release
  cp "target/release/updisk" "$bin/updisk"
)

echo "done -> $bin"
ls -1 "$bin"
