# CPU Scenario

## Symptom
One of the services pegs CPU cores. The other four sleep.

## USE method walk-through

| Dimension    | Tool                      | What you should see                          |
|--------------|---------------------------|----------------------------------------------|
| Utilization  | `top`, `mpstat -P ALL 1`  | One or more cores at ~100% in user time      |
| Saturation   | `vmstat 1`                | `r` column (run queue) > #CPUs               |
| Errors       | `dmesg`, `perf`           | Usually none for pure CPU work               |

## Pinning it to a container

```bash
docker stats --no-stream
docker exec <name> top -bn1 | head
```

The container whose `CPU %` is highest is the culprit. Inside, you'll see
`stress-ng` processes running the `matrixprod` workload.

## Why this is a USE problem

High **utilization** + a **saturated** run queue with no **errors** is the
classic CPU-bound signature. The fix in real life is to scale out, throttle the
hot workload, or identify the hot code path with `perf top`.
