# Hotpath Scenario

## Symptom
A Python HTTP service is driven by a local load generator that hits `/search`,
`/report`, `/aggregate`, and `/export`. One handler has a nested for-loop, so
the service burns CPU even though the request mix looks ordinary.

This is the layer past the basic CPU scenario: USE method tells you the
*resource* is saturated, but you still need a *profiler* to find the
*function*.

## USE method walk-through

| Dimension    | Tool                        | What you should see                              |
|--------------|-----------------------------|--------------------------------------------------|
| Utilization  | `top`, process checks       | The Python service process near 100% CPU         |
| Saturation   | `vmstat 1`                  | `r` (run-queue) creeping up on a busy host       |
| Errors       | `dmesg`                     | None                                             |

## Drilling into the function

Once you've identified the hot process, attach `py-spy`:

```bash
./use-practice status
py-spy top --pid <service-pid>
```

`py-spy top` will show one handler (`handle_search`, `handle_report`,
`handle_aggregate`, or `handle_export`) sitting at ~100% Own time. That
function name is the URL route, which is how you know which endpoint is the
bug.

For a one-shot snapshot of all live stacks:

```bash
py-spy dump --pid <service-pid>
```

For a flame graph over a 30-second window:

```bash
py-spy record --pid <service-pid> --output flame.svg --duration 30
```

## Why this is the right next step after the CPU scenario

The pure-`stress-ng` CPU scenario stops at "which process is hot". Real
production bugs continue: *which function inside that process?* The USE
method is deliberately resource-first &mdash; it tells you where to point the
profiler, not what the profiler will show. This scenario walks both halves of
that workflow.

Real fixes from this point look like: vectorise the inner loop, cache
intermediate results, push the work to a background job, or short-circuit
the request when inputs are large.

## TSA paragraph

This is Executing-dominant like the plain CPU scenario, but the useful next
step is a function-level profiler. TSA and USE both point at CPU; `py-spy`
answers which handler owns the time.

## Notes

- `py-spy` may need elevated ptrace permissions depending on the VM's kernel
  settings.
- For non-Python hot paths you'd use `perf top -p <pid>`. That needs perf
  installed for the host kernel.
