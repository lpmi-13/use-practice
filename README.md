# use-practice

Hands-on practice scenarios for Brendan Gregg's
[**USE method**](https://www.brendangregg.com/usemethod.html). Each scenario
spins up a small Docker Compose stack where one of several services is
randomly chosen to misbehave on a single resource. Your job is to find the
culprit by checking **Utilization**, **Saturation**, and **Errors** for each
resource type.

## Resources covered

| Scenario | Workload tool | Randomised inputs                                     |
|----------|---------------|-------------------------------------------------------|
| `cpu`    | `stress-ng`   | culprit service, worker count (1-4)                   |
| `memory` | `stress-ng`   | culprit service, resident size (300-800 MB)           |
| `disk`   | `fio`         | culprit service, block size, iodepth, rw pattern      |
| `network`| `iperf3`      | culprit service, sink port, bandwidth, parallel flows |

The "culprit" is one of five services with realistic names (`api`, `worker`,
`cache`, `queue`, `auth`); the others sit idle. Every run picks a fresh
combination so it isn't the same problem twice.

## Requirements

- Docker with the Compose v2 plugin (`docker compose ...`)
- Linux host with `top`, `vmstat`, `iostat`, `sar`, `ss`, `free` (the `sysstat`
  and `iproute2` packages cover most of these)

## Quick start

```bash
# Pick one at random; the resource type is hidden until you call ./reveal.sh
./run.sh

# Or target a specific resource (gives you a heads-up + USE-method hints)
./run.sh cpu
./run.sh memory
./run.sh disk
./run.sh network

# Diagnose using your host tools (top, iostat -xz 1, sar -n DEV 1, ...)

./reveal.sh        # see which service + parameters were actually used
./stop-all.sh      # tear everything down
```

## Workflow

1. `./run.sh` (random) or `./run.sh <resource>`.
2. Look at the four resource families one by one:
   - **CPU** &mdash; `top`, `mpstat -P ALL 1`, `vmstat 1` (run-queue `r`)
   - **Memory** &mdash; `free -m`, `vmstat 1` (`si`/`so`), `/proc/pressure/memory`
   - **Disk** &mdash; `iostat -xz 1` (`%util`, `aqu-sz`, `await`)
   - **Network** &mdash; `sar -n DEV 1`, `ss -s`, `ip -s link`
3. When you find a saturated resource, drill into per-container metrics:
   ```bash
   docker stats --no-stream
   docker exec <name> top -bn1
   ```
4. `./reveal.sh` to check your answer.
5. `./stop-all.sh` when finished.

Each scenario directory has its own `SOLUTION.md` with the USE-method
walk-through and pointers on what the fix would look like in production.

## Layout

```
.
├── run.sh              # top-level launcher (random by default)
├── reveal.sh           # print active scenario's answer
├── stop-all.sh         # stop everything
├── tools/Dockerfile    # shared image (stress-ng, fio, iperf3, sysstat, ...)
└── scenarios/
    ├── cpu/
    ├── memory/
    ├── disk/
    └── network/
        ├── docker-compose.yml
        ├── start.sh        # randomises parameters, brings stack up
        ├── stop.sh
        ├── reveal.sh
        └── SOLUTION.md
```

## Notes

- Host-level tools (`iostat`, `sar`, `vmstat`) see aggregate kernel counters,
  which is correct &mdash; the USE method targets resources, not processes.
  Drill into per-container metrics only after you've identified the resource.
- The disk scenario uses `--direct=1` so the page cache doesn't mask the load.
- The network scenario shares the default Compose bridge; `sar -n DEV 1`
  on the host will show the bridge/veth interfaces.
- The `.env` and `.answer` files inside each scenario directory are
  gitignored. Don't peek at them &mdash; that's what `reveal.sh` is for.
```
