# syntax=docker/dockerfile:1

# Build the Go dispatcher and generic Go workload (cpu/memory/network +
# baseline). Both are stdlib-only, so no network access is needed at build time.
FROM golang:1.24-bookworm AS gobuild
ENV GOPROXY=off GOFLAGS=-mod=mod
WORKDIR /src/use-practice
COPY use-practice/go.mod ./
COPY use-practice/cmd ./cmd
COPY use-practice/internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/use-practice ./cmd/use-practice

WORKDIR /src/loadgen/go
COPY use-practice/loadgen/go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/uworker ./cmd/uworker

# Build the Rust io_uring disk workload and kernel-wait workload. Crates are
# fetched from crates.io at build time and pinned by the committed Cargo.lock.
FROM rust:1-bookworm AS rustbuild
WORKDIR /src
COPY use-practice/loadgen/rust/updisk ./
RUN cargo build --release --locked \
  && install -D target/release/updisk /out/updisk \
  && install -D target/release/uwait /out/uwait

FROM ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04

USER root
ENV HOME=/root

COPY use-practice /opt/use-practice
COPY playground/iximiuz/image/use-practice-bootstrap.service /etc/systemd/system/use-practice-bootstrap.service
COPY playground/iximiuz/image/use-practice-privileged /tmp/use-practice-privileged

COPY --from=gobuild /out/use-practice /opt/use-practice/use-practice
COPY --from=gobuild /out/uworker /opt/use-practice/bin/uworker
COPY --from=rustbuild /out/updisk /opt/use-practice/bin/updisk
COPY --from=rustbuild /out/uwait /opt/use-practice/bin/uwait

RUN <<'EOF'
set -eu

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  ethtool \
  git \
  iproute2 \
  iotop \
  jq \
  procps \
  psmisc \
  sudo \
  sysstat
rm -rf /var/lib/apt/lists/*

chmod 755 /opt/use-practice/use-practice
chmod 755 /opt/use-practice/bin/uworker \
  /opt/use-practice/bin/updisk \
  /opt/use-practice/bin/uwait
install -D -m 0755 /tmp/use-practice-privileged /usr/local/libexec/use-practice-privileged
rm -f /tmp/use-practice-privileged
find /opt/use-practice/scenarios -name '*.sh' -exec chmod 755 {} +

if id laborant >/dev/null 2>&1; then
  chown -R root:root /opt/use-practice
  install -d -m 0755 /var/lib/use-practice
  install -d -o laborant -g laborant -m 0755 /var/lib/use-practice/state
  ln -sfn /opt/use-practice /home/laborant/use-practice
  chown -h laborant:laborant /home/laborant/use-practice
  printf 'laborant ALL=(root) NOPASSWD: /usr/local/libexec/use-practice-privileged *\n' \
    > /etc/sudoers.d/use-practice
  chmod 0440 /etc/sudoers.d/use-practice
  grep -qxF 'cd ~/use-practice' /home/laborant/.bashrc || echo 'cd ~/use-practice' >> /home/laborant/.bashrc
fi

cat > /usr/local/bin/use-practice <<'EOF_WRAPPER'
#!/usr/bin/env bash
export USE_PRACTICE_ROOT=/opt/use-practice
export USE_PRACTICE_STATE_DIR=/var/lib/use-practice/state
exec /opt/use-practice/use-practice "$@"
EOF_WRAPPER
chmod 755 /usr/local/bin/use-practice

for cmd in bash curl ip jq setpriv use-practice vmstat; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "missing expected tool: ${cmd}" >&2
    exit 1
  }
done

for workload in uworker updisk uwait; do
  [ -x "/opt/use-practice/bin/${workload}" ] || {
    echo "missing workload binary: ${workload}" >&2
    exit 1
  }
done

ln -sf /etc/systemd/system/use-practice-bootstrap.service \
  /etc/systemd/system/multi-user.target.wants/use-practice-bootstrap.service
EOF

USER laborant
ENV HOME=/home/laborant
ENV USE_PRACTICE_ROOT=/opt/use-practice
ENV USE_PRACTICE_STATE_DIR=/var/lib/use-practice/state
