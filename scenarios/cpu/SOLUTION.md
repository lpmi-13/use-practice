# CPU Scenario

## Symptom
One of the services pegs CPU cores. The other services sleep.

## USE method walk-through

| Dimension    | Tool                      | What you should see                          |
|--------------|---------------------------|----------------------------------------------|
| Utilization  | `top`, `mpstat -P ALL 1`  | One or more cores at ~100% in user time      |
| Saturation   | `vmstat 1`                | `r` column (run queue) > #CPUs               |
| Errors       | `dmesg`, `perf`           | Usually none for pure CPU work               |

## Pinning it to a host process

```bash
./use-practice status
top -bcn1 w512
ps -eo pid,ppid,pgid,stat,pcpu,pmem,args --sort=-pcpu | head
```

The recorded service process running `stress-ng` is the culprit. The service
name is only an identity for the lab workload; the host signal is ordinary CPU
pressure from a real process.

## TSA paragraph

This is Executing-dominant: the busy threads are spending their time on CPU.
If you switch from USE to thread-state analysis, the dominant state should
agree with the CPU utilization signal rather than point to sleep, I/O wait, or
quota throttling.

## Why this is a USE problem

High **utilization** + a **saturated** run queue with no **errors** is the
classic CPU-bound signature. The fix in real life is to scale out, throttle the
hot workload, or identify the hot code path with `perf top`.
