# Network Scenario

## Symptom
One service-like host process runs parallel `iperf3` flows against a local
sink at a chosen Mbit/s. When the scenario can create a veth pair and network
namespace, the traffic is visible on that host interface. Otherwise it falls
back to loopback and tells you to include `lo` in interface checks.

## USE method walk-through

| Dimension    | Tool                          | What you should see                                   |
|--------------|-------------------------------|-------------------------------------------------------|
| Utilization  | `sar -n DEV 1`                | Backing iface near link rate; one interface dominates |
| Saturation   | `ss -tin`, `ss -s`            | TCP retrans, `cwnd` collapses, RTT jitter             |
| Errors       | `ip -s link`, `sar -n EDEV 1` | drops/overruns on a specific interface                |

## Pinning it to host processes

```bash
./use-practice status
ss -tnp | grep iperf3
ip -s link
```

The recorded client service with active iperf3 connections is the culprit.
TCP variants emphasize retransmits and queue pressure; UDP variants make
loss/jitter and interface drops easier to see.

## TSA paragraph

This is Sleeping-dominant on socket wait once the offered load outruns the
network path. USE shows the busy interface, queues, retransmits, or drops;
thread-state analysis explains the application-side waiting.

## Why this is a USE problem

A pipe at line rate is **utilization**; queues + retransmits are
**saturation**; drops on the interface are **errors**. All three can light up
when bandwidth is over-subscribed. Fixes: throttle (`tc`), rate-limit at the
application, give the noisy service its own network, or shape egress.
