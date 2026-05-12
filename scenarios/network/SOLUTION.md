# Network Scenario

## Symptom
One service runs parallel `iperf3` flows against the `sink` container at a
chosen Mbit/s. The Docker bridge interface saturates.

## USE method walk-through

| Dimension    | Tool                          | What you should see                                   |
|--------------|-------------------------------|-------------------------------------------------------|
| Utilization  | `sar -n DEV 1`                | Backing iface near link rate; one veth dominates      |
| Saturation   | `ss -tin`, `ss -s`            | TCP retrans, `cwnd` collapses, RTT jitter             |
| Errors       | `ip -s link`, `sar -n EDEV 1` | drops/overruns on a specific veth                     |

## Pinning it to a container

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.NetIO}}'
docker exec <name> ip -s link show eth0
```

The container with runaway `NET I/O` is the culprit. Inside, `ss -tnp` shows
active iperf3 connections to `sink:<port>`.

## Why this is a USE problem

A pipe at line rate is **utilization**; queues + retransmits are
**saturation**; drops on the veth are **errors**. All three light up here
when bandwidth is over-subscribed. Fixes: throttle (tc), rate-limit at the
application, give the noisy service its own network or shape egress.
