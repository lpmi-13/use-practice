#!/usr/bin/env bash
# Build the dispatcher and workload binaries for local runs. The iximiuz image
# builds these the same way in a multi-stage Docker build.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$root/bin"
mkdir -p "$bin"

echo "building Go dispatcher (use-practice)..."
(
  cd "$root"
  rm -f "$root/use-practice"
  CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$root/use-practice" ./cmd/use-practice
)

echo "building Go workload (uworker)..."
(
  cd "$root/loadgen/go"
  CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$bin/uworker" ./cmd/uworker
)

echo "building Rust workloads (updisk, uwait)..."
(
  cd "$root/loadgen/rust/updisk"
  cargo build --release
  target_dir="${CARGO_TARGET_DIR:-target}"
  cp "$target_dir/release/updisk" "$bin/updisk"
  cp "$target_dir/release/uwait" "$bin/uwait"
)

echo "done -> $root/use-practice and $bin"
ls -1 "$bin"
