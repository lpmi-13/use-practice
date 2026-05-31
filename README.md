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
| `cpu` | busy compute worker | Host CPU utilization and run queue |
| `memory` | large resident set | Resident memory, PSI, swap/OOM pressure |
| `disk` | direct random block I/O | Device utilization, queue depth, await |
| `network` | sustained socket traffic | Interface throughput, TCP saturation, drops |

Each scenario runs a small purpose-built workload binary rather than a
recognizable load-testing tool. The binary is copied to a per-run, service-named
path and launched with no arguments, so `ps`, `top`, and `/proc/<pid>/cmdline`
show only the service identity — there is no `stress-ng`/`fio`/`iperf3` command
line to grep for. Each run chooses a randomized service-like identity and a
fresh run ID. Blind runs intentionally avoid naming the resource type, so the
exercise is solved by following the system signals rather than by
pattern-matching names.

## Requirements

- Ephemeral Linux VM, preferably iximiuz Labs.
- Linux host tools such as `top`, `vmstat`, `iostat`, `sar`, `ss`, and `free`.
- The workload binaries (`upcpu`, `upmem`, `updisk`, `upnet`), built into
  `./bin`. The disk workload uses `io_uring` direct I/O, so the backing
  filesystem must support `O_DIRECT` (it falls back to buffered I/O otherwise).

The iximiuz rootfs build compiles the workload binaries (Go + Rust) in a
multi-stage Docker build and ships them in the image. For local manual runs,
build them first with:

```bash
bash scripts/build.sh   # needs the Go and Rust toolchains
```

## Quick Start

```bash
# Pick one at random; the resource type is hidden until reveal.
./run.sh

# Or target a specific resource.
./run.sh cpu
./run.sh memory
./run.sh disk
./run.sh network

./reveal.sh
./stop-all.sh
```

The same commands are available through the dispatcher:

```bash
./use-practice run [scenario]
./use-practice reveal
./use-practice stop
./use-practice list
./use-practice status
```

## Investigation Flow

1. Start a blind or named scenario.
2. Check the host-level USE signals, either directly or through
   `/home/adam/projects/use-tool`:
   - CPU: `top`, `mpstat -P ALL 1`, `vmstat 1`
   - Memory: `free -m`, `vmstat 1`, `cat /proc/pressure/memory`
   - Disk: `iostat -xz 1`, `pidstat -d 1`
   - Network: `sar -n DEV 1`, `ss -s`, `ip -s link`
3. Pivot from the resource signal to the responsible process or service-like
   workload using normal host tools such as `top`, `ps`, `pidstat`, `iotop`,
   `ss`, or the relevant profiler.
4. Use `./use-practice status` if you need the active run ID without revealing
   the resource type.
5. Use `./reveal.sh` to see the answer and the scenario's `SOLUTION.md` for
   the walkthrough.
6. Use `./stop-all.sh` when finished.

## iximiuz Deployment

The iximiuz path follows the same rootfs-image pattern as the companion labs:
the repo, `use-tool`, workload packages, and bootstrap service are baked into a
custom root filesystem image, then `playground/iximiuz/manifest.yaml` points the
playground at that image.

Rootfs GHCR package:

```text
ghcr.io/lpmi-13/use-practice-rootfs
```

Build and optionally push the rootfs image:

```bash
docker login ghcr.io

# Downloads the latest use-tool release by default.
IMAGE_TAG=v1 PUSH_ROOTFS_IMAGE=1 bash scripts/build-rootfs-image.sh
```

This creates:

```text
ghcr.io/lpmi-13/use-practice-rootfs:${IMAGE_TAG}
```

Set `USE_TOOL_VERSION=v0.5.0` to pin a specific `use-tool` release tag. Leave it
unset, or set `USE_TOOL_VERSION=latest`, to resolve the latest GitHub release at
build time.

The build script updates `playground/iximiuz/manifest.yaml` after a successful
build. Verify the published image reference before creating or updating the
playground:

```bash
grep -n "source: oci://" playground/iximiuz/manifest.yaml
```

Then publish the custom playground:

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

The playground opens directly into `~/use-practice` as the `laborant` user.
Use `./run.sh` to start a random scenario and `use-tool practice system` to
investigate it.

## Layout

```text
.
|-- use-practice          # dispatcher
|-- run.sh                # compatibility wrapper for use-practice run
|-- reveal.sh             # compatibility wrapper for use-practice reveal
|-- stop-all.sh           # compatibility wrapper for use-practice stop
|-- bin/                  # compiled workload binaries (built, git-ignored)
|-- loadgen/
|   |-- go/               # upcpu, upmem, upnet (Go)
|   `-- rust/updisk/      # updisk: io_uring direct-I/O worker (Rust)
|-- playground/
|   `-- iximiuz/          # playground manifest, rootfs Dockerfile, bootstrap unit
|-- scripts/
|   |-- build.sh          # builds the workload binaries into ./bin
|   `-- lib.sh            # shared host-process runtime helpers
`-- scenarios/
    |-- cpu/
    |-- memory/
    |-- disk/
    `-- network/
```

`.env`, `.answer`, and runtime state files inside scenario directories are
generated at runtime and ignored by git.
