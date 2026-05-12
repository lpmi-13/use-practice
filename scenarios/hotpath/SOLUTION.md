# Hotpath Scenario

## Symptom
Five identical Python HTTP services sit behind a `loadgen` container that
hits each service evenly across `/search`, `/report`, `/aggregate`, `/export`.
One service has a nested for-loop inlined into exactly one of those handlers,
so its CPU burns far hotter than the others &mdash; even though every service
sees the same request rate.

This is the layer past the basic CPU scenario: USE method tells you the
*resource* is saturated, but you still need a *profiler* to find the
*function*.

## USE method walk-through

| Dimension    | Tool                        | What you should see                              |
|--------------|-----------------------------|--------------------------------------------------|
| Utilization  | `top`, `docker stats`       | One container near 100% CPU, others light        |
| Saturation   | `vmstat 1`                  | `r` (run-queue) creeping up on a busy host       |
| Errors       | `dmesg`                     | None                                             |

## Drilling into the function

Once you've identified the hot container, attach `py-spy`:

```bash
NAME=<hot-container>
PID=$(docker exec "$NAME" pgrep -f server.py)
docker exec "$NAME" py-spy top --pid "$PID"
```

`py-spy top` will show one handler (`handle_search`, `handle_report`,
`handle_aggregate`, or `handle_export`) sitting at ~100% Own time. That
function name *is* the URL route &mdash; that's how you know which endpoint
is the bug.

For a one-shot snapshot of all live stacks:

```bash
docker exec "$NAME" py-spy dump --pid "$PID"
```

For a flame graph over a 30-second window:

```bash
docker exec "$NAME" py-spy record --pid "$PID" --output /tmp/flame.svg --duration 30
docker cp "$NAME":/tmp/flame.svg .
```

## Why this is the right next step after the CPU scenario

The pure-`stress-ng` CPU scenario stops at "which container is hot". Real
production bugs continue: *which function inside that container?* The USE
method is deliberately resource-first &mdash; it tells you where to point
the profiler, not what the profiler will show. This scenario walks both
halves of that workflow.

Real fixes from this point look like: vectorise the inner loop, cache
intermediate results, push the work to a background job, or short-circuit
the request when inputs are large.

## Notes

- `py-spy` needs `SYS_PTRACE`; the compose file grants it.
- For non-Python hot paths you'd use `perf top -p <pid>` from the host
  (which sees the container's threads via `/proc`). That needs perf
  installed on the host kernel.
