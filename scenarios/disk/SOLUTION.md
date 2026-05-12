# Disk Scenario

## Symptom
One service is pounding the shared `scratch` volume with `fio`. Read/write
latency on whatever underlying block device backs Docker rises.

## USE method walk-through

| Dimension    | Tool                              | What you should see                               |
|--------------|-----------------------------------|---------------------------------------------------|
| Utilization  | `iostat -xz 1`                    | `%util` close to 100% on the backing device       |
| Saturation   | `iostat -xz 1`                    | `aqu-sz` > 1, `r_await`/`w_await` climbing        |
| Errors       | `dmesg \| grep -i 'i/o error'`    | Usually none in containers; would matter on bare metal |

## Pinning it to a container

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.BlockIO}}'
docker exec <name> cat /proc/1/io
```

The container with runaway `BlockIO` is the culprit. Inside, `pidstat -d 1` or
`cat /proc/<pid>/io` will show fio doing the I/O.

## Why this is a USE problem

A saturated device queue with high await is the textbook disk bottleneck.
`%util` alone can lie on SSDs (parallelism), so always pair it with `aqu-sz`
and `await`. Fixes: throttle the noisy neighbor (`--device-write-bps`),
separate volumes, or move hot data onto faster storage.
