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
| `cpu` | `stress-ng --cpu` | Host CPU utilization and run queue |
| `memory` | `stress-ng --vm` | Resident memory, PSI, swap/OOM pressure |
| `disk` | `fio --direct=1` | Device utilization, queue depth, await |
| `network` | `iperf3` | Interface throughput, TCP saturation, drops |
| `hotpath` | Python HTTP service | CPU-hot process, then profiler drill-down |

Each run chooses a randomized service-like identity and a fresh run ID. Blind
runs intentionally avoid naming the resource type, so the exercise is solved
by following the system signals rather than by pattern-matching names.

## Requirements

- Ephemeral Linux VM, preferably iximiuz Labs.
- Linux host tools such as `top`, `vmstat`, `iostat`, `sar`, `ss`, and `free`.
- Workload tools used by scenarios, such as `stress-ng`, `fio`, `iperf3`,
  Python, and any profiler used by the hotpath scenario.

The iximiuz rootfs build installs these tools for the learner. Local manual
runs need them installed on the host.

## Quick Start

```bash
# Pick one at random; the resource type is hidden until reveal.
./run.sh

# Or target a specific resource.
./run.sh cpu
./run.sh memory
./run.sh disk
./run.sh network
./run.sh hotpath

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

Build and optionally push the rootfs image:

```bash
docker login ghcr.io

# Uses ../use-tool/use-tool by default. Set USE_TOOL_BIN if needed.
IMAGE_TAG=v1 PUSH_ROOTFS_IMAGE=1 bash scripts/build-rootfs-image.sh
```

This creates:

```text
ghcr.io/lpmi-13/use-practice-rootfs:${IMAGE_TAG}
```

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
|-- playground/
|   `-- iximiuz/          # playground manifest, rootfs Dockerfile, bootstrap unit
|-- scripts/
|   `-- lib.sh            # shared host-process runtime helpers
`-- scenarios/
    |-- cpu/
    |-- memory/
    |-- disk/
    |-- network/
    `-- hotpath/
```

`.env`, `.answer`, and runtime state files inside scenario directories are
generated at runtime and ignored by git.
