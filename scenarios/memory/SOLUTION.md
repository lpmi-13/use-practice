# Memory Scenario

## Symptom
One service holds a large resident set. On hosts with limited RAM you'll see
swap pressure or OOM-kills.

## USE method walk-through

| Dimension    | Tool                                    | What you should see                                   |
|--------------|-----------------------------------------|-------------------------------------------------------|
| Utilization  | `free -m`                               | `used` near total, `available` tiny                   |
| Saturation   | `vmstat 1`, `cat /proc/pressure/memory` | `si`/`so` (swap-in/out) > 0, PSI `some avg10` rising  |
| Errors       | `dmesg \| grep -i oom`                  | OOM-killer firing on the culprit                      |

## Pinning it to a host process

```bash
./use-practice status
top -bcn1 w512
ps -eo pid,ppid,pgid,stat,pcpu,pmem,rss,args --sort=-rss | head
```

Several look-alike services are running; the one with disproportionate resident
memory is the culprit. `top` sorted by RES (`Shift+M`) or `ps --sort=-rss` will
show it holding the bytes, well above the small steady footprint of the decoys.

## TSA paragraph

When the host has swap enabled, this becomes Anon-Paging-dominant: threads
lose time to memory pressure and page movement. Without swap, it may look more
like Executing until the kernel reaches OOM territory, so pair thread state
with PSI and process memory counters.

## Why this is a USE problem

High **utilization** with rising **saturation** (swap traffic / PSI) is the
classic memory pressure signature. **Errors** (OOM kills) only appear once the
kernel gives up. Fixes: cap the workload, find the leak with `pmap`, or scale
memory out.
