# Disk Scenario

## Symptom
One service-like host process is pounding a bounded local file with direct,
random block I/O. Read/write latency on whatever block device backs the working
directory rises. The workload uses one fixed-size 256 MiB file, so running it
longer increases block I/O counters but does not keep allocating more disk.

## USE method walk-through

| Dimension    | Tool                              | What you should see                               |
|--------------|-----------------------------------|---------------------------------------------------|
| Utilization  | `iostat -xz 1`                    | `%util` close to 100% on the backing device       |
| Saturation   | `iostat -xz 1`                    | `aqu-sz` > 1, `r_await`/`w_await` climbing        |
| Errors       | `dmesg \| grep -i 'i/o error'`    | Usually none in this lab; would matter on bare metal |

## Pinning it to a host process

```bash
./use-practice status
pidstat -d 1
iotop -bn1
cat /proc/<pid>/io
```

Several look-alike services are running, and the decoys each do a little
occasional I/O, so don't just look for the one process touching the disk —
look for the one doing the *most*. `pidstat -d 1`, `iotop`, or
`cat /proc/<pid>/io` will show one process dominating reads/writes.

The scratch data lives under the scenario's `.runtime/` directory and
disappears when the scenario is stopped.

## TSA paragraph

This is Sleeping-dominant on disk wait: the culprit's useful work is blocked
behind storage latency. USE finds the saturated block device; TSA explains why
the workload is not making progress even when it is not burning CPU.

## Why this is a USE problem

A saturated device queue with high await is the textbook disk bottleneck.
`%util` alone can lie on SSDs (parallelism), so always pair it with `aqu-sz`
and `await`. Fixes: throttle the noisy neighbor (`--device-write-bps`),
separate volumes, or move hot data onto faster storage.
