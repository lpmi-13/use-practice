# use-practice

Hands-on practice scenarios for Brendan Gregg's
[USE method](https://www.brendangregg.com/usemethod.html). Each run starts a
randomized host-level workload on a Linux VM. Your job is to correlate what
the investigation tools report with the real system state by checking
utilization, saturation, and errors.

## Intended Environment

This project is intended to run inside an ephemeral training VM, specifically
iximiuz Labs. The scenarios deliberately create CPU, memory, disk, network, or
application-level pressure, and can make the machine slow, noisy, or unstable
while they are running.

It is possible to run the scenarios on your own Linux system, but it is not
advised. Use a disposable VM where losing local state or temporarily degrading
the machine is acceptable.

## Scenarios

| Scenario | Workload | Primary signal |
|---|---|---|
| `cpu` | busy compute or non-I/O kernel wait | CPU utilization, run queue, load, D-state wait |
| `memory` | large resident set or reclaim churn | Available memory, PSI, swap/OOM pressure |
| `disk` | direct random block I/O | Device utilization or queue depth/await |
| `network` | sustained or backpressured socket traffic | Interface throughput, TCP saturation, drops |

Each scenario starts a fleet of 5–10 service-like processes. **One** of them
runs the resource-specific load profile above; the rest run a low-activity
"baseline" (a small resident set, sub-1% CPU, and occasional tiny disk/network
blips) so the host looks like a real, lightly-loaded fleet. Your job is to find
the culprit by its USE signal, not by spotting the only busy process.

The workload is three generic binaries — `uworker` (Go: cpu/memory/network +
baseline), `updisk` (Rust + io_uring: disk + baseline), and `uwait` (Rust:
non-I/O kernel waits + baseline) — rather than a recognizable load-testing
tool. Within a scenario every service runs the *same* binary, copied to a
per-run, service-named path and launched with no arguments; its parameters come
from an adjacent config file it unlinks on startup. So `ps`, `top`,
`/proc/<pid>/cmdline`, and `/proc/<pid>/exe` show only the service identity —
there is no `stress-ng`/`fio`/`iperf3` command line to grep for, and the culprit
is byte-identical to the decoys. Each run also chooses a fresh run ID, and blind
runs avoid naming the resource type, so the exercise is solved by following the
system signals rather than by pattern-matching names.

The CPU scenario has three profiles. `utilization` keeps CPUs busy without
intentionally creating a runnable backlog. `runq` creates ordinary runnable
run-queue pressure with more busy workers than CPUs. `kernelwait` combines CPU
burners with many threads blocked in a non-I/O uninterruptible kernel wait
(`vfork`), so learners can see why load average must be paired with `vmstat
r/b`, thread state, and wait-channel evidence. For targeted local testing, set
run `use-practice run cpu` and choose `utilization`, `runq`, or
`kernelwait` from the profile selector.

The memory scenario has three profiles. `resident` is utilization-focused:
one service holds a large resident set with little expected ongoing reclaim
after allocation settles. `pressure` keeps a large resident set and adds bounded
anonymous mapping churn so learners can pair low available memory with PSI or
swap activity. `oom` creates a cgroup v2 memory limit for the culprit child
process, allocates beyond that limit, and restarts the child after each memcg
OOM kill. The OOM profile defaults to a cgroup limit of 80% of current
`MemAvailable`, while keeping at least 512 MB or 10% of host RAM outside the
limit as host reserve. For targeted local testing, run
`use-practice run memory` and choose `resident`, `pressure`, or `oom` from
the profile selector. The OOM profile can be tuned with `OOM_LIMIT_PCT` (10-90)
and `OOM_RESERVE_MB`.

The disk scenario has two profiles. `utilization` issues continuous
queue-depth-one direct random I/O, keeping the backing device busy without
building a large sustained queue. `saturation` issues short high-depth I/O
bursts separated by idle gaps so queue depth and await spike without sustained
full-device busy time, exposing queueing that `%util` alone would miss. For
targeted local testing, run `use-practice run disk` and choose
`utilization` or `saturation` from the profile selector.

The network scenario has three profiles. `utilization` sends steady
high-throughput TCP to a draining sink. `saturation` uses a slow-reading TCP
sink to create socket backpressure without high actual throughput. `highload`
keeps the original offered-load TCP/UDP behavior where utilization and
saturation can appear together. For targeted local testing, run
`use-practice run network` and choose `utilization`, `saturation`, or
`highload` from the profile selector.

### Why There Is No CPU "Errors" Scenario

The scenarios exercise the USE triad — utilization, saturation, and errors —
wherever a workload can legitimately produce each signal. The clearest
workload-reachable error is in the `memory` scenario, which can drive swap and
OOM kills. There is deliberately no scenario that produces *CPU* errors.

In Brendan Gregg's USE method a CPU error is a hardware fault — a Machine Check
Exception (MCE), an ECC/cache parity error, or thermal throttling — reported via
`/sys/devices/system/machinecheck/`, EDAC, the per-core `thermal_throttle`
counters, or the kernel log. Utilization and saturation are products of
*workload* that any process can generate on demand; a CPU error is a product of
*hardware*, and userspace cannot make one happen. The only facilities that can
fabricate one deterministically — `mce-inject` (software MCE injection) and ACPI
APEI `einj` (firmware error injection) — need root, debugfs, x86, and (for EINJ)
server-class firmware. None of that is available in the ephemeral, unprivileged
training VM, so a CPU-errors scenario could never reliably reproduce its target
state.

## Requirements

- Ephemeral Linux VM, preferably iximiuz Labs.
- Linux host tools such as `top`, `vmstat`, `iostat`, `sar`, `ss`, and `free`.
- The workload binaries (`uworker`, `updisk`, `uwait`), built into `./bin`. The disk
  workload uses `io_uring` direct I/O, so the backing filesystem must support
  `O_DIRECT` (it falls back to buffered I/O otherwise).

The `use-practice` CLI is a dispatcher for this repo layout, not a standalone
single-binary distribution. It expects the scenario scripts under `scenarios/`,
the shared Bash helpers under `scripts/`, and the service workload binaries in
`./bin` to exist together. In the iximiuz lab image those pieces are packaged
under `/opt/use-practice`; for local runs, build the workload binaries first.
The remote VM exposes `use-practice` as the user-facing command; the remaining
shell scripts are scenario/runtime internals.

The iximiuz rootfs build compiles the dispatcher and workload binaries
(Go + Rust) in a multi-stage Docker build and ships them in the image. For
local manual runs, build them first with:

```bash
bash scripts/build.sh   # needs the Go and Rust toolchains
```

## Quick Start

```bash
# Open a selector for run, reveal, stop, list, or status.
use-practice

# Open a selector for random, CPU, memory, disk, or network.
use-practice run

# Or target a specific resource directly, then choose its profile.
use-practice run cpu
use-practice run memory
use-practice run disk
use-practice run network

# Keep the old blind-random behavior explicitly.
use-practice run random

use-practice reveal
use-practice stop
```

Direct aliases also work: `use-practice random`, `use-practice cpu`,
`use-practice memory`, `use-practice disk`, and `use-practice network`.
Running `use-practice run` with no scenario opens the resource selector.
Choosing `cpu`, `memory`, `disk`, or `network` opens a second selector for that
resource's profiles, with `random` as the first option. In non-interactive
shells both selectors fall back to `random` so automation does not block.

## Investigation Flow

1. Start a blind or named scenario.
2. Check the host-level USE signals, either directly or through
   `use-tool practice system`:
   - CPU: `top`, `mpstat -P ALL 1`, `vmstat 1`,
     `ps -eLo pid,tid,stat,wchan,comm`
   - Memory: `free -m`, `vmstat 1`, `cat /proc/pressure/memory`
   - Disk: `iostat -xz 1`, `pidstat -d 1`
   - Network: `sar -n DEV 1`, `ss -s`, `ip -s link`
3. Pivot from the resource signal to the responsible process or service-like
   workload using normal host tools such as `top`, `ps`, `pidstat`, `iotop`,
   `ss`, or the relevant profiler.
4. Use `use-practice status` if you need the active run ID and live
   PID/service inventory without revealing the resource type.
5. Use `use-practice reveal` to see the answer and the scenario's
   `SOLUTION.md` for the walkthrough.
6. Use `use-practice stop` when finished.

## iximiuz Deployment

The iximiuz path follows the same rootfs-image pattern as the companion labs:
the repo, workload packages, and bootstrap service are baked into a custom root
filesystem image, then `playground/iximiuz/manifest.yaml` points the playground
at that image. The manifest startup script installs the latest `use-tool`
release when a lab starts.

Rootfs GHCR package:

```text
ghcr.io/lpmi-13/use-practice-rootfs
```

Build and optionally push the rootfs image:

```bash
docker login ghcr.io

IMAGE_TAG=v10 PUSH_ROOTFS_IMAGE=1 bash scripts/build-rootfs-image.sh
```

This creates:

```text
ghcr.io/lpmi-13/use-practice-rootfs:${IMAGE_TAG}
```

For local packaging validation without Docker, use:

```bash
DRY_RUN=1 bash scripts/build-rootfs-image.sh
```

For a local Docker image build without changing the checked-in manifest, set
`UPDATE_MANIFEST=0`:

```bash
UPDATE_MANIFEST=0 ROOTFS_IMAGE=use-practice-rootfs:local bash scripts/build-rootfs-image.sh
```

By default, the build script updates `playground/iximiuz/manifest.yaml` after a
successful build. Verify the published image reference before creating or
updating the playground:

```bash
grep -n "source: oci://" playground/iximiuz/manifest.yaml
```

Publish or update the custom playground:

```bash
labctl auth login

# First publish
labctl playground create use-practice-5e9d1d9a \
  --base flexbox \
  --file playground/iximiuz/manifest.yaml

# Later updates
labctl playground update use-practice-5e9d1d9a \
  --file playground/iximiuz/manifest.yaml \
  --force
```

Start a live playground session from the manifest and run the lab smoke script
with the session ID from `labctl playground start --quiet`:

```bash
labctl playground start use-practice-4ce4816f \
  --file playground/iximiuz/manifest.yaml \
  --quiet \
  --safety-disclaimer-consent

scripts/smoke-iximiuz-live.sh <playground-session-id>
```

The live smoke uses `labctl cp` and `labctl ssh` to validate the packaged
dispatcher, selectors, `cpu -> kernelwait`, `disk -> saturation`,
`network -> highload`, and `memory -> oom` in the actual iximiuz VM.

The playground opens directly into `~/use-practice` as the `laborant` user.
Use `use-practice` for the command selector, or `use-practice run` to start a
scenario, then use `use-tool practice system` to investigate it.

## Layout

```text
.
|-- cmd/use-practice/     # Go dispatcher entrypoint
|-- internal/cli/         # command parsing, selectors, and dispatch
|-- bin/                  # compiled workload binaries (built, git-ignored)
|-- loadgen/
|   |-- go/               # uworker: cpu/memory/network + baseline (Go)
|   `-- rust/updisk/      # updisk: io_uring disk; uwait: kernel waits (Rust)
|-- playground/
|   `-- iximiuz/          # playground manifest, rootfs Dockerfile, bootstrap unit
|-- scripts/
|   |-- build.sh          # builds the dispatcher and workload binaries locally
|   |-- build-rootfs-image.sh
|   |-- smoke-iximiuz-live.sh
|   |-- iximiuz-live-smoke-remote.sh
|   `-- lib.sh            # shared host-process runtime helpers
`-- scenarios/
    |-- cpu/
    |-- memory/
    |-- disk/
    `-- network/
```

`.env`, `.answer`, and runtime state files inside scenario directories are
generated at runtime and ignored by git.
