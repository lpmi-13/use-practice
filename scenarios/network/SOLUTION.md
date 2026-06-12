# Network Scenario

## Symptom
One service-like host process runs flows against a local sink. The run chooses
one of three profiles:

- Utilization profile: a draining TCP sink receives steady high-throughput
  traffic. Interface throughput should dominate, while socket queues and
  retransmits should stay comparatively quiet.
- Saturation profile: a slow-reading TCP sink creates sender-side backpressure
  at low actual throughput. Look for `Send-Q`, `sndbuf_limited`,
  `rwnd_limited`, or similar socket evidence rather than a high interface rate.
- High-load profile: the original offered-load profile. TCP or UDP traffic can
  drive utilization and saturation together.

When the scenario can create a veth pair and network namespace, the traffic is
visible on that host interface. Otherwise it falls back to loopback and tells
you to include `lo` in interface checks.

## USE method walk-through

| Dimension    | Tool                          | What you should see                                   |
|--------------|-------------------------------|-------------------------------------------------------|
| Utilization  | `sar -n DEV 1`                | Utilization/high-load: one interface dominates throughput |
| Saturation   | `ss -tin`, `ss -s`            | Saturation/high-load: Send-Q, retrans, rwnd/sndbuf-limited, drops |
| Errors       | `ip -s link`, `sar -n EDEV 1` | drops/overruns on a specific interface                |

## Pinning it to host processes

```bash
./use-practice status
ss -tnp
ip -s link
```

Several look-alike services are running; the decoys emit only tiny loopback
chatter, so the talker with sustained connections to the sink is the culprit.
For the saturation profile, the culprit may not be the highest-throughput
process; instead, identify the connection with persistent send queue or TCP
limited-time evidence.

## TSA paragraph

The utilization profile is mostly Executing/Sending: the application is moving
bytes and the interface is the relevant utilization surface. The saturation
profile is Sleeping-dominant on socket wait: the sender is blocked behind the
receiver or socket buffers. The high-load profile can show both at once.

## Why this is a USE problem

A pipe at line rate is **utilization**; queues, send-buffer pressure,
receive-window limits, retransmits, or drops are **saturation**. Drops/errors
on the interface are **errors**. Fixes: throttle (`tc`), rate-limit at the
application, give the noisy service its own network, increase receiver capacity,
or shape egress.
