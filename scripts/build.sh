#!/usr/bin/env bash
# Build the workload binaries into ./bin. The iximiuz image builds these the
# same way in a multi-stage Docker build; this script is for local runs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$root/bin"
mkdir -p "$bin"

echo "building Go workload (uworker)..."
(
  cd "$root/loadgen/go"
  CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$bin/uworker" ./cmd/uworker
)

echo "building Rust disk workload (updisk)..."
(
  cd "$root/loadgen/rust/updisk"
  cargo build --release
  cp "target/release/updisk" "$bin/updisk"
)

echo "done -> $bin"
ls -1 "$bin"
