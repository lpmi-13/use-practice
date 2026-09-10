# Disk Scenario

## Symptom
One service-like host process is issuing direct, random block I/O against a
bounded local file. The run chooses one of three disk profiles:

- Utilization profile: continuous queue-depth-one I/O. The backing device stays
  busy, but requests should not build a large sustained queue.
- Saturation profile: short high-depth bursts followed by idle gaps. Queue depth
  and await should spike, but the device should not show sustained full-window
  busy time.
- Latency profile: sustained deep-queue (128-256) large-block (512K-1M) I/O.
  The device is driven to its bandwidth ceiling, so requests queue at the device
  and per-op await climbs into the hundreds of milliseconds. Here `%util` is
  pegged too -- this is the profile to reach for when a fast SSD/virtio device
  needs to show real, sustained await (shallow small-I/O bursts queue briefly
  but each op still completes sub-millisecond, so they never build latency).

The utilization and saturation profiles use one fixed-size 256 MiB file; the
latency profile uses a larger 1 GiB file so its in-flight set scatters instead
of fitting in device cache. Either way, running longer increases block I/O
counters but does not keep allocating more disk.

## USE method walk-through

| Dimension    | Tool                              | What you should see                               |
|--------------|-----------------------------------|---------------------------------------------------|
| Utilization  | `iostat -xz 1`                    | Utilization profile: `%util` high, `aqu-sz` near 1 |
| Saturation   | `iostat -xz 1`                    | Saturation profile: `aqu-sz`/await spikes without sustained `%util` near 100; Latency profile: deep `aqu-sz` (100+) and `await` in the hundreds of ms with `%util` pegged |
| Errors       | `dmesg \| grep -i 'i/o error'`    | Usually none in this lab; check timestamps for pre-existing host messages |

## Pinning it to a host process

```bash
./use-practice status
pidstat -d 1
iotop -bn1
cat /proc/<pid>/io
```

Several look-alike services are running, and the decoys each do a little
occasional I/O, so don't just look for the one process touching the disk. Look
for the process whose I/O pattern matches the active profile: steady dominant
I/O for utilization runs, repeated short bursts for saturation runs, or heavy
sustained large-block I/O for latency runs.
`pidstat -d 1`, `iotop`, or `cat /proc/<pid>/io` will identify the service.

The scratch data lives under the scenario's `.runtime/` directory and
disappears when the scenario is stopped.

## TSA paragraph

The utilization profile is Sleeping-dominant on disk service time: the culprit
keeps the device busy with one request at a time. The saturation profile is
Sleeping-dominant on queueing: the culprit creates bursts where requests wait
behind other requests before reaching the device. The latency profile is
Sleeping-dominant on both at once: a deep queue of large requests keeps the
device pegged AND makes each request wait a long time for service.

## Why this is a USE problem

High `%util` and high queue depth answer different USE questions. A device can
be busy without a deep queue, and short high-depth bursts can expose queueing
without keeping the device busy for the whole sample window. `%util` alone can
also lie on SSDs because of parallelism, so pair it with `aqu-sz` and `await`.
Fixes: throttle the noisy neighbor (`--device-write-bps`), separate volumes, or
move hot data onto faster storage.
