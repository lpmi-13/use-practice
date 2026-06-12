# syntax=docker/dockerfile:1

# Build the generic Go workload (cpu/memory/network + baseline). Stdlib only,
# so no network access is needed at build time.
FROM golang:1.24-bookworm AS gobuild
ENV GOPROXY=off GOFLAGS=-mod=mod
WORKDIR /src
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
COPY playground/iximiuz/image/bootstrap-use-practice.sh /opt/iximiuz-labs/bootstrap-use-practice.sh
COPY playground/iximiuz/image/use-practice-bootstrap.service /etc/systemd/system/use-practice-bootstrap.service

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

chmod 755 /opt/use-practice/use-practice \
  /opt/use-practice/run.sh \
  /opt/use-practice/reveal.sh \
  /opt/use-practice/stop-all.sh \
  /opt/use-practice/scripts/wait-lab-ready.sh \
  /opt/iximiuz-labs/bootstrap-use-practice.sh
chmod 755 /opt/use-practice/bin/uworker \
  /opt/use-practice/bin/updisk \
  /opt/use-practice/bin/uwait
find /opt/use-practice/scenarios -name '*.sh' -exec chmod 755 {} +

if id laborant >/dev/null 2>&1; then
  chown -R laborant:laborant /opt/use-practice
  ln -sfn /opt/use-practice /home/laborant/use-practice
  chown -h laborant:laborant /home/laborant/use-practice
  printf 'laborant ALL=(root) NOPASSWD: /usr/sbin/ip, /usr/bin/ip, /usr/bin/tee, /usr/bin/kill\n' \
    > /etc/sudoers.d/use-practice
  chmod 0440 /etc/sudoers.d/use-practice
  grep -qxF 'cd ~/use-practice' /home/laborant/.bashrc || echo 'cd ~/use-practice' >> /home/laborant/.bashrc
fi

cat > /usr/local/bin/use-practice <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/use-practice
exec ./use-practice "$@"
EOS
cat > /usr/local/bin/use-practice-run <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/use-practice
exec ./run.sh "$@"
EOS
cat > /usr/local/bin/use-practice-reveal <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/use-practice
exec ./reveal.sh "$@"
EOS
cat > /usr/local/bin/use-practice-stop <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/use-practice
exec ./stop-all.sh "$@"
EOS
chmod 755 /usr/local/bin/use-practice \
  /usr/local/bin/use-practice-run \
  /usr/local/bin/use-practice-reveal \
  /usr/local/bin/use-practice-stop

for cmd in bash curl ip jq use-practice vmstat; do
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
