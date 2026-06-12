# Memory Scenario

## Symptom
One service holds a large resident set. The run chooses one of two memory
profiles:

- Resident profile: the culprit holds a large anonymous working set and then
  mostly stays steady. This is a utilization-focused profile: available memory
  should be low, while `vmstat si/so` and memory PSI should quiet down after the
  initial allocation settles.
- Pressure profile: the culprit holds a large anonymous working set and also
  churns bounded temporary mappings. This is the combined utilization plus
  saturation profile: available memory should be low, and reclaim stalls should
  show up in PSI and, where swap is configured, `vmstat si/so`.

## USE method walk-through

| Dimension    | Tool                                    | What you should see                                   |
|--------------|-----------------------------------------|-------------------------------------------------------|
| Utilization  | `free -m`, `/proc/meminfo`              | `MemAvailable` / `available` low                     |
| Saturation   | `vmstat 1`, `cat /proc/pressure/memory` | Resident: quiet after settling. Pressure: PSI `some`/`full` or `si`/`so` activity |
| Errors       | `dmesg \| grep -i oom`                  | Usually none; OOM-killer lines mean the scenario overshot or the host was already constrained |

## Pinning it to a host process

```bash
./use-practice status
top -bcn1 w512
ps -eo pid,ppid,pgid,stat,pcpu,pmem,rss,args --sort=-rss | head
```

Several look-alike services are running; the one with disproportionate resident
memory is the culprit. `top` sorted by RES (`Shift+M`) or `ps --sort=-rss` will
show it holding the bytes, well above the small steady footprint of the decoys.
For pressure runs, repeat `vmstat 1` or PSI capture long enough to catch the
churn cycle.

## TSA paragraph

The resident profile is mostly memory utilization: the bytes are occupied, but
the workload should not keep tasks stalled once the allocation has settled. The
pressure profile is Anon-Reclaim or Anon-Paging dominant: useful work loses
time to reclaim, page faults, and possibly swap movement. PSI is the most
portable saturation signal when swap is absent.

## Why this is a USE problem

Low available memory is **utilization**. Reclaim stalls, swap traffic, and PSI
are **saturation**. A host can be heavily used without currently stalling, so
do not cite `used` or RSS alone as saturation evidence. **Errors** (OOM kills)
only appear once the kernel gives up. Fixes: cap the workload, find the leak
with `pmap`, or scale memory out.
