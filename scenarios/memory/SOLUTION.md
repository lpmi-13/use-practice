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

## Pinning it to a container

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
```

The container with disproportionate `MEM USAGE` is the leak. Inside, `top`
sorted by RES (`Shift+M`) will show `stress-ng-vm` holding the bytes.

## Why this is a USE problem

High **utilization** with rising **saturation** (swap traffic / PSI) is the
classic memory pressure signature. **Errors** (OOM kills) only appear once the
kernel gives up. Fixes: cap the container's memory (`--memory`), find the leak
with `pmap`, or scale memory out.
