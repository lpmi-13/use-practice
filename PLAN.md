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

The dispatcher surface stays small:

```text
use-practice                   Interactive subcommand selector.
use-practice run [scenario]    Start a scenario. No arg -> resource selector.
use-practice reveal            Print the answer for the active scenario.
use-practice stop              Tear down the active scenario.
use-practice list              List available scenarios.
use-practice status            Show the active run ID and live workload PIDs.
```

`use-practice run cpu|memory|disk|network` opens a second selector for that
resource's profile/scenario variant. `use-practice random` and
`use-practice cpu|memory|disk|network` remain aliases for the corresponding
`use-practice run ...` commands. Non-interactive selector paths fall back to
`random` so automation does not block.

Scenario output should continue to encourage pairing with:

```bash
use-tool practice system
```

## Go CLI Migration Progress

The dispatcher migration is now in progress. The migration keeps the Bash
scenario scripts and workload binaries as the runtime source of truth while
replacing the top-level dispatcher with a Go CLI.

Completed:

- Documented the migration requirements in `GOLANG_CLI_MIGRATION_PLAN.md`,
  including selector hierarchy, workload preservation, cleanup contracts, and
  VM validation requirements.
- Began implementation by preserving current behavior as the baseline before
  introducing the Go dispatcher.
- Added the Go dispatcher module, command entrypoint, selector-aware dispatch
  logic, and unit tests for command selection, aliases, environment mapping,
  blind random behavior, broad stop cleanup, status output, and reveal output.
- Documented in `README.md` that the Go CLI is intentionally coupled to this
  repo layout, scenario scripts, shared Bash helpers, and separate workload
  binaries.
- Removed the previous shell dispatcher and top-level compatibility wrappers
  after live VM validation, leaving `use-practice` as the user-facing command.
- Updated local build and iximiuz rootfs packaging to compile the Go dispatcher
  as `use-practice` while continuing to package `uworker`, `updisk`, and
  `uwait`.
- Updated VM bootstrap readiness checks to require all three workload binaries:
  `uworker`, `updisk`, and `uwait`.
- Verified the Go unit tests, shell syntax for changed scripts, local build of
  the dispatcher and workload binaries, and non-invasive CLI smoke checks for
  `list`, `status`, and `--help`.
- Added selector rendering/key-reader tests and verified top-level interactive
  selection through a pseudo-terminal by selecting `list`.
- Verified arrow-key navigation through a pseudo-terminal by moving the
  top-level selector to `list` and selecting it.
- Verified the run selector quit path through a pseudo-terminal; it exits 130
  and leaves no active scenario.
- Ran `go vet ./...` with no findings.
- Added `DRY_RUN=1` support to `scripts/build-rootfs-image.sh` and verified the
  generated rootfs build context includes the Go dispatcher source, scenario
  scripts, Go workload source, and Rust workload source while excluding
  generated `bin/` and `target/` artifacts.
- Covered status redaction in Go tests, replacing the old shell compatibility
  test.
- Added and passed an ExecRunner-backed test that launches temporary scenario
  shell scripts, verifies pre-run stop scripts are invoked, and confirms the
  selected profile environment reaches the start script.
- Built a local rootfs image as `use-practice-rootfs:cli-migration-local` with
  `UPDATE_MANIFEST=0` and verified container-level smoke checks for
  `/usr/local/bin/use-practice list`, `/usr/local/bin/use-practice status`, and
  executable presence of `use-practice`, `uworker`, `updisk`, and `uwait`.
- Ran bounded live scenario smokes inside the local rootfs container and cleaned
  them up with `use-practice stop`: `cpu -> utilization`, `cpu -> kernelwait`
  (`uwait`), `disk -> saturation` (`updisk`), and `network -> highload`
  (`uworker`, loopback fallback in Docker).
- Added `scripts/smoke-iximiuz-live.sh` and
  `scripts/iximiuz-live-smoke-remote.sh` to run live remote lab validation via
  `labctl ssh`/`labctl cp`.
- Verified the live-smoke remote script inside the local rootfs container with
  `WAIT_LAB_READY=0`, `RUN_MEMORY_OOM=0`, and `REQUIRE_NETWORK_VETH=0`, covering
  safe CLI checks plus `cpu -> kernelwait`, `disk -> saturation`, and
  `network -> highload`.
- Re-ran `go test ./...`, `go vet ./...`, and shell syntax checks for the
  changed Bash scripts after adding the `labctl` live-smoke workflow.
- Built and pushed the migrated iximiuz rootfs image as
  `ghcr.io/lpmi-13/use-practice-rootfs:v10`, updated the checked-in manifest and
  version constants to point at it, and started a live remote iximiuz Labs VM
  from that manifest with `labctl`.
- Ran `scripts/smoke-iximiuz-live.sh 6a3284e92f2649649867fad5` successfully
  against the live VM. This validated the browser-terminal selector path,
  `cpu -> kernelwait`, `disk -> saturation`, `network -> highload` using a
  veth/netns interface, and `memory -> oom` cgroup `oom_kill` behavior.
- Stopped the validation playground after the smoke passed.
- Pushed the updated manifest permanently to iximiuz with
  `labctl playground update use-practice-4ce4816f --file playground/iximiuz/manifest.yaml --force`
  and verified the hosted manifest now references
  `oci://ghcr.io/lpmi-13/use-practice-rootfs:v10`.
- Removed top-level compatibility wrappers and per-scenario reveal shims from
  the repo and remote image. The rootfs now exposes only `/usr/local/bin/use-practice`
  as the user-facing command, symlinked to the Go dispatcher under
  `/opt/use-practice`, with `USE_PRACTICE_ROOT=/opt/use-practice`.
- Removed additional low-value shell helpers: `scripts/push-images.sh`,
  `scripts/test-status-output.sh`, `scripts/wait-lab-ready.sh`,
  `scripts/update-version-refs.sh`, `scripts/lib/versions.sh`, and the
  separate VM bootstrap script. Readiness waiting now lives in the manifest and
  live-smoke script, the bootstrap checks live directly in the systemd unit, and
  rootfs manifest/default-tag updates are handled by `scripts/build-rootfs-image.sh`.
- Fixed rootfs packaging so image metadata, local default tag state, and the
  manifest stay aligned on the same rootfs tag before Docker builds.
- Reduced the remote rootfs further by packaging only `scripts/lib.sh` under
  `/opt/use-practice/scripts`; local build/deploy/smoke scripts are no longer
  present in the lab VM image.
- Built and pushed `ghcr.io/lpmi-13/use-practice-rootfs:v10`, verified in a
  container that the remote image contains only `scripts/lib.sh` under
  `/opt/use-practice/scripts`, passed the full live iximiuz smoke against
  playground session `6a331b491fbb21764a69674e`, stopped that validation
  playground, and pushed the `v10` manifest permanently to iximiuz.

Remaining:

- No known migration blockers. The remaining shell scripts are scenario runtime,
  build, deployment, and smoke-test internals; the local and remote user-facing
  command surface is `use-practice`.

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
