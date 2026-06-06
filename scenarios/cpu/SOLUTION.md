# CPU Scenario

## Symptom
One service creates CPU pressure. The exact profile varies by run:

- `Runnable run-queue pressure`: many busy worker threads compete for CPU time.
- `CPU burners plus non-I/O D-state kernel wait`: busy worker threads consume
  CPU while many peer threads block in an uninterruptible kernel wait caused by
  `vfork`, not by disk or network I/O.

## USE method walk-through

| Dimension    | Tool                      | What you should see                          |
|--------------|---------------------------|----------------------------------------------|
| Utilization  | `top`, `mpstat -P ALL 1`  | One or more cores near 100% in user time     |
| Saturation   | `vmstat 1`                | `r` high for runnable backlog; `b` high for D-state wait |
| Load         | `uptime`, `/proc/loadavg` | Inflated by both runnable and D-state tasks  |
| Errors       | `dmesg`, `journalctl -k`  | Usually none for workload-driven CPU pressure |

## Pinning it to a host process

```bash
./use-practice status
top -bcn1 w512
top -H -bcn1 w512
ps -eo pid,ppid,pgid,stat,pcpu,pmem,args --sort=-pcpu | head
ps -eLo pid,tid,ppid,stat,wchan:32,pcpu,comm,args | awk '$4 ~ /R|D/'
```

Several look-alike services are running. Sort by `%CPU` to find the service
burning CPU, then switch to thread view when the answer mentions D-state
waiters. In the kernel-wait profile, the active service should have many
threads in `D` with a wait channel like `kernel_clone`; those waits come from
`vfork`, so they are non-I/O uninterruptible sleeps. Ordinary userspace mutex
or futex contention would normally show as interruptible sleep instead.

## TSA paragraph

The run-queue profile is Executing-dominant: the useful work is on CPU, and
`vmstat r` should dominate.

The kernel-wait profile is mixed. The CPU burner threads are Executing, while
the waiter threads are Sleeping in a non-I/O kernel wait. Load average alone is
therefore ambiguous: it counts runnable tasks and D-state tasks. Pair it with
`vmstat r/b`, thread states, and wait channels before calling it pure CPU
saturation.

## Why this is a USE problem

High **utilization** plus a saturated runnable queue is the classic CPU-bound
signature. High load with many `D` tasks needs more evidence: the CPU may still
be busy, but part of the load is blocked kernel wait rather than runnable work.
Fixes in real life depend on the dominant state: scale or profile hot code for
Executing-heavy workloads; investigate the kernel wait site for D-state-heavy
workloads.
