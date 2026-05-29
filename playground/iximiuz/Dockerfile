# syntax=docker/dockerfile:1
FROM ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04

USER root
ENV HOME=/root

COPY use-practice /opt/use-practice
COPY use-tool/use-tool /usr/local/bin/use-tool
COPY playground/iximiuz/image/bootstrap-use-practice.sh /opt/iximiuz-labs/bootstrap-use-practice.sh
COPY playground/iximiuz/image/use-practice-bootstrap.service /etc/systemd/system/use-practice-bootstrap.service

RUN <<'EOF'
set -eu

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  fio \
  git \
  iperf3 \
  iproute2 \
  iotop \
  jq \
  procps \
  psmisc \
  python3 \
  python3-pip \
  stress-ng \
  sudo \
  sysstat
rm -rf /var/lib/apt/lists/*

python3 -m pip install --break-system-packages --no-cache-dir py-spy

chmod 755 /usr/local/bin/use-tool
chmod 755 /opt/use-practice/use-practice \
  /opt/use-practice/run.sh \
  /opt/use-practice/reveal.sh \
  /opt/use-practice/stop-all.sh \
  /opt/use-practice/scripts/wait-lab-ready.sh \
  /opt/iximiuz-labs/bootstrap-use-practice.sh
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

for cmd in bash curl fio iperf3 ip jq python3 py-spy stress-ng use-practice use-tool vmstat; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "missing expected tool: ${cmd}" >&2
    exit 1
  }
done

ln -sf /etc/systemd/system/use-practice-bootstrap.service \
  /etc/systemd/system/multi-user.target.wants/use-practice-bootstrap.service
EOF

USER laborant
ENV HOME=/home/laborant
