# use-practice - Plan

`use-practice` is a training harness that generates real performance problems
on an ephemeral Linux VM, so a learner can investigate them with the companion
performance-analysis tools:

- `use-tool` - USE method per resource
- `tsa-tool` - Thread State Analysis
- `workload-tool` - workload characterization
- `flame-tool` - flame graph capture and rendering

The near-term direction is host-only. Kubernetes can come back later as an
advanced environment, but the default practice loop should create strong,
host-visible signals without requiring the learner to know about pods,
containers, or cluster mechanics.

## Purpose

Give the learner a live, reproducible misbehaving system to investigate.
That is the entire job. The harness:

- Starts one randomized host-level workload or local service scenario.
- Tells the learner which resource it picked, or picks one randomly and hides
  the resource type.
- Provides a `reveal` mechanism that explains what was wrong and how the
  canonical investigation would have found it.
- Tears the workload down cleanly.

It does not:

- Grade the learner's investigation.
- Track which scenarios the learner has seen.
- Score submissions or compare them against an answer key.
- Ask learners to remediate the issue.

Assessment and persistence are out of scope for now. The point is a low-friction
practice environment that the tools can be exercised against.

## Target Environment

The intended runtime is an ephemeral iximiuz Labs VM. Running the harness on a
personal machine is possible but not advised, because scenarios deliberately
consume CPU, memory, disk, network, or application runtime.

The host-only approach fits this deployment model:

- The VM is disposable, so workload side effects are acceptable.
- Host-level tools see the full signal without container or Kubernetes
  attribution layers.
- Cleanup is simpler than a cluster, and leftover state is easier to audit.
- The learner practices the same shell commands that `use-tool` teaches.

## Why Host-Only First

The current learning objective is correlation from observed tool signals to
real system state. For that objective, Kubernetes adds more puzzle surface than
it removes. If the learner has to be told which pod to inspect, the scenario is
too scaffolded; if pod-level load is too small relative to the VM, host-level
USE signals become weak.

Host-only scenarios make the signal obvious enough to teach:

- CPU pressure should show up in `top`, `mpstat`, `vmstat`, load average, and
  CPU PSI. Load average must be cross-checked with runnable vs blocked task
  state because Linux load includes D-state tasks as well as runnable tasks.
- Memory pressure should show up in `free`, `vmstat`, memory PSI, and OOM or
  eviction-like symptoms where applicable.
- Disk pressure should show up in `iostat`, I/O PSI, and per-process I/O tools.
- Network pressure should show up in `sar -n DEV`, `ss`, and interface error or
  drop counters where the scenario can create a real non-loopback path.
- Hotpath scenarios should bridge from high CPU to a process and then to a
  profiler view.

Kubernetes can still be useful later for a separate learning objective:
cgroup limits, pod attribution, and orchestration-specific debugging.

## Scenario Catalog

The first host-only catalog should stay small:

| Name | Primary signal | Culprit profile |
|---|---|---|
| `cpu` | CPU utilization high; run queue, load, D-state evidence | busy compute worker, run-queue worker, or non-I/O kernel-wait worker |
| `memory` | RSS high; memory PSI or swap pressure | large resident set or reclaim churn |
| `disk` | device `%util` or `await`/`aqu-sz`, I/O PSI | io_uring direct random I/O |
| `network` | interface throughput, TCP saturation, drops | draining or backpressured socket source/sink over a veth/netns path |

Each scenario starts a fleet of 5–10 service-like processes. One runs the
culprit profile above; the rest run a low-activity "baseline" (small resident
set, sub-1% CPU, occasional tiny disk/network blips) so the culprit must be
found by signal magnitude, not by being the only active process.

The fleet is three generic workload binaries — `uworker` (Go:
cpu/memory/network + baseline), `updisk` (Rust + io_uring: disk + baseline),
and `uwait` (Rust: non-I/O kernel waits + baseline) — rather than a
recognizable load-testing tool. Behavior is chosen by a `mode=` line in a
config file. Within a scenario every service runs the *same* binary, staged to
a per-run, service-named path and launched with no arguments and its config in
an adjacent file it unlinks on start, so `ps`, `top`, `/proc/<pid>/cmdline`,
and `/proc/<pid>/exe` reveal only the service identity and the culprit is
byte-identical to the decoys.

Each run should choose plausible service-like identities (`payments-api`,
`reports-worker`, `catalog-indexer`, etc.) and write local state files that
`reveal` can use. Names should not reveal the resource type.

## CLI Surface

The shell-driver surface stays small:

```text
use-practice run [scenario]    Start a scenario. No arg -> random, blind banner.
use-practice reveal            Print the answer for the active scenario.
use-practice stop              Tear down the active scenario.
use-practice list              List available scenarios.
use-practice status            Show the active run ID and live workload PIDs.
```

`use-practice run` with no argument should print host-level USE starting points
and should encourage pairing with:

```bash
use-tool practice system
```

## Implementation Shape

Prefer ordinary host processes over containers:

- Start background processes with a run-specific process title or environment.
- Record PIDs in scenario-local runtime files.
- Use traps and `stop` scripts to kill only recorded PIDs.
- Keep generated disk state under scenario-owned runtime directories.
- Keep workload intensity bounded so scenarios are obvious but do not make the
  VM unrecoverable.

For network scenarios, loopback-only traffic is usually too artificial because
many network investigation flows filter `lo`. Prefer a simple veth pair or
network namespace when the lab environment permits it; otherwise document the
loopback limitation clearly.

## Out of Scope

- No grading.
- No historical progress tracking.
- No remediation tasks.
- No default Kubernetes dependency.
- No container metrics shortcut as the primary answer path.
- No production safety guarantee for non-disposable machines.
