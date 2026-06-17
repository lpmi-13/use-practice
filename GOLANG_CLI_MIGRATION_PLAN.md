# Go CLI Migration Plan

## Goal

Replace the top-level `use-practice` shell dispatcher with a Go CLI while
leaving the existing scenario scripts and workload binaries in place.

The migration should improve interactive selector reliability, especially in
browser terminals, without changing the behavior of the underlying CPU, memory,
disk, and network scenarios. The only deliberate user-facing behavior change is
that an interactive bare `use-practice` command should open a subcommand
selector instead of immediately entering the run selector.

## Scope

Migrate:

- Bare `use-practice` command selection
- `use-practice run`
- `use-practice reveal`
- `use-practice stop`
- `use-practice list`
- `use-practice status`
- Existing direct run aliases: `use-practice random`, `use-practice cpu`,
  `use-practice memory`, `use-practice disk`, `use-practice network`
- Resource selector: `random`, `cpu`, `memory`, `disk`, `network`
- Per-resource profile/scenario variant selectors:
  - CPU: `random`, `utilization`, `runq`, `kernelwait`
  - Memory: `random`, `resident`, `pressure`, `oom`
  - Disk: `random`, `utilization`, `saturation`
  - Network: `random`, `utilization`, `saturation`, `highload`

Do not migrate yet:

- `scenarios/*/start.sh`
- `scenarios/*/stop.sh`
- `scripts/lib.sh`
- Go/Rust workload internals beyond what existing scenarios already need

## Current Workload Inventory

The remote iximiuz VM currently runs service-like host processes by staging
generic workload binaries under per-run service names. Preserve this model; the
Go dispatcher must not start the workload binaries directly.

Current required workload binaries:

- `uworker` (Go): CPU utilization/run-queue, memory resident/pressure/OOM,
  network source/sink, and baseline decoys.
- `updisk` (Rust): disk utilization/saturation and baseline decoys.
- `uwait` (Rust): CPU `kernelwait` profile and baseline decoys.

The scenario scripts copy these binaries from `/opt/use-practice/bin` into a
per-run runtime directory, write adjacent config files, and launch them under
service-like process names. This preserves the current `ps`, `top`,
`/proc/<pid>/cmdline`, and `/proc/<pid>/exe` training behavior.

## Proposed Architecture

Keep the scenario implementation in Bash and make the Go binary the dispatcher.

```text
use-practice             Go binary
scenarios/*/*.sh         Existing scenario scripts
scripts/lib.sh           Existing shared Bash helpers
bin/uworker              Existing Go workload binary
bin/updisk               Existing Rust disk workload binary
bin/uwait                Existing Rust kernel-wait workload binary
```

The Go CLI should shell out to the existing scripts using the same working
directories and environment variables the shell dispatcher uses today. The
VM image should expose `/usr/local/bin/use-practice` as the only user-facing
entrypoint.

## Command Behavior

- Interactive bare `use-practice` opens a subcommand selector with:
  `run`, `reveal`, `stop`, `list`, `status`.
- Non-interactive bare `use-practice` preserves the current automation-friendly
  behavior: treat it as `use-practice run`, and allow the run selector fallback
  to choose `random`.
- `use-practice run` opens the resource selector in an interactive terminal with:
  `random`, `cpu`, `memory`, `disk`, `network`.
- `use-practice run random` starts a blind random resource scenario.
- `use-practice run cpu|memory|disk|network` opens the profile/scenario variant
  selector for that resource in an interactive terminal with that resource's
  profiles, including `random`.
- `use-practice cpu|memory|disk|network` remains an alias for
  `use-practice run <resource>`.
- `use-practice random` remains an alias for `use-practice run random`.
- Non-interactive selector paths fall back to `random` so automation does not block.
- Blind random runs suppress the selected resource's startup output and show
  only the blind banner.
- Explicit resource runs print `==> Running scenario: <resource>` and then run
  the scenario script normally.
- `reveal`, `stop`, `list`, and `status` keep their current output shape unless
  a deliberate compatibility change is made.
- `use-practice stop` runs every existing `scenarios/*/stop.sh`, preserving the
  current broad cleanup behavior.

## Launch And State Contracts

Preserve these dispatcher-to-script contracts:

- Before any new scenario starts, run all existing scenario stop scripts quietly,
  matching the current `stop_all_quietly` behavior. This prevents stale
  processes, network namespaces, veth links, cgroups, and state files from
  contaminating the next run.
- For blind random runs, pick one resource randomly, run
  `scenarios/<resource>/start.sh` with that script's working directory, suppress
  the script's startup output, and leave the resource-specific profile
  environment unset so the scenario script chooses its own random profile.
- For explicit resource runs, set only the selected resource's profile
  environment variable and run the existing start script normally.
- Do not parse or rewrite `.answer`, `.env`, `.run-id`, `.pids`, `.processes`,
  `.netns`, `.links`, or `.cgroups` formats during this migration.
- `status` discovers the active scenario by the same markers as today:
  `scenarios/<resource>/.run-id` or `scenarios/<resource>/.answer`.
- `status` prints only the active run ID plus PID/service/state from
  `.processes`, preserving the current non-revealing output.
- `reveal` prints the active scenario's `.answer` verbatim.

## Selector Implementation

Reuse the proven terminal-key approach from `/home/adam/projects/use-tool`:

- Enter raw mode for interactive selector input.
- Support arrows and `j`/`k`.
- Support numeric jumps.
- Support Enter to choose.
- Support `q` to quit.
- Support `?` for expanded help.
- Use full-screen redraw for browser-terminal compatibility.
- Fall back to line/non-interactive behavior when stdin is not a terminal.

Selector hierarchy:

```text
use-practice
  -> subcommand selector: run, reveal, stop, list, status

use-practice run
  -> resource selector: random, cpu, memory, disk, network

use-practice run cpu
  -> CPU profile/scenario selector: random, utilization, runq, kernelwait

use-practice run memory
  -> Memory profile/scenario selector: random, resident, pressure, oom

use-practice run disk
  -> Disk profile/scenario selector: random, utilization, saturation

use-practice run network
  -> Network profile/scenario selector: random, utilization, saturation, highload
```

Avoid adding a third-party TUI dependency unless the local `use-tool` selector
code proves too costly to adapt.

## Environment Mapping

When launching a selected profile, set the same environment variables used by
the current scenario scripts:

```text
cpu      -> CPU_PROFILE
memory   -> MEM_PROFILE
disk     -> DISK_PROFILE
network  -> NETWORK_PROFILE
```

Examples:

```text
use-practice run memory
  selector chooses oom
  Go runs: MEM_PROFILE=oom scenarios/memory/start.sh

use-practice run random
  Go picks one resource randomly
  Go runs: scenarios/<picked>/start.sh with profile left random
```

`use-practice run <resource>` with a selected profile of `random` should set the
resource's environment variable to `random`; the existing scenario script then
chooses one concrete profile from its current option list.

## Packaging Changes

Add a Go module or command package for the dispatcher, for example:

```text
cmd/use-practice/main.go
internal/selector/...
internal/dispatch/...
```

Update the rootfs build to compile and install the Go dispatcher:

```text
go build -trimpath -ldflags="-s -w" -o /opt/use-practice/use-practice ./cmd/use-practice
```

Preserve the existing workload build and install steps:

```text
(cd loadgen/go && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /opt/use-practice/bin/uworker ./cmd/uworker)
(cd loadgen/rust/updisk && cargo build --release --locked)
install -D loadgen/rust/updisk/target/release/updisk /opt/use-practice/bin/updisk
install -D loadgen/rust/updisk/target/release/uwait /opt/use-practice/bin/uwait
```

After live VM validation, remove the old shell dispatcher and compatibility
wrappers so users interact with only `use-practice`.

Update VM bootstrap/readiness checks to verify all required workload binaries:
`uworker`, `updisk`, and `uwait`.

## Test Plan

Unit tests:

- Command parsing for all supported subcommands and direct aliases.
- Bare `use-practice` selector options and dispatch.
- Resource/profile option lists.
- Profile-to-environment mapping.
- Selector rendering.
- Non-interactive fallback behavior.
- Pre-run quiet cleanup is invoked before scenario start.
- Status output does not leak scenario details beyond PID/service/state.

Integration tests:

- Interactive selector harness for bare `use-practice` dispatch.
- `use-practice list`
- `use-practice status` with no active scenario.
- `use-practice reveal` with no active scenario.
- `use-practice`, when non-interactive, does not block.
- `use-practice cpu` behaves like `use-practice run cpu`.
- `use-practice random` behaves like `use-practice run random`.
- Explicit resource/profile launch with environment mapping.
- Blind random launch suppresses scenario-specific startup output.
- `use-practice stop` calls every scenario stop script and removes process,
  cgroup, and network state created by a run.

VM smoke tests:

- Bare `use-practice` selector works in the iximiuz browser terminal.
- Selecting `run` opens the resource selector.
- `use-practice run` selector works in the iximiuz browser terminal.
- Selecting a resource opens the second profile selector.
- `use-practice cpu` opens the CPU profile selector.
- Selecting `cpu -> kernelwait` starts the Rust `uwait` workload.
- Selecting `memory -> oom` starts the cgroup OOM scenario.
- `memory.events` `oom_kill` increases persistently.
- Selecting `disk -> saturation` starts the Rust `updisk` workload.
- Selecting `network -> highload` starts the Go `uworker` source/sink workload.
- VM remains responsive.
- `use-practice stop` cleans up processes and cgroups.
- Bootstrap readiness fails if any required workload binary is missing:
  `uworker`, `updisk`, or `uwait`.

## Estimated Effort

- Basic Go dispatcher parity: 1 day
- Selector port from `use-tool`: 0.5-1 day
- Tests for parsing, aliases, selectors, env mapping, cleanup, and status:
  0.5-1 day
- Build/rootfs packaging updates: 0.5 day
- VM validation and polish: 0.5 day

Expected total: 2-3 focused days.

## Recommended Migration Sequence

1. Add the Go dispatcher alongside the existing shell dispatcher.
2. Implement `list`, `status`, `reveal`, and `stop`, preserving current output
   and cleanup behavior.
3. Implement `run random`, direct resource aliases, and explicit
   `run <resource>` by shelling out to existing scripts.
4. Port the selector from `use-tool`.
5. Add the bare `use-practice` subcommand selector.
6. Add the `run` resource selector.
7. Add the per-resource profile selectors and environment mapping.
8. Add tests.
9. Update rootfs packaging to install the Go binary as `use-practice` while
   preserving `uworker`, `updisk`, and `uwait` build/install checks.
10. Remove the shell dispatcher and compatibility wrappers once VM validation
    passes.
11. Validate in iximiuz.

Status: implemented and validated. The migrated rootfs image was published as
`ghcr.io/lpmi-13/use-practice-rootfs:v10`, the manifest was updated to use it,
and `scripts/smoke-iximiuz-live.sh 6a331b491fbb21764a69674e` passed against a
live iximiuz Labs VM before the validation playground was stopped. The cleanup
phase removed top-level wrapper scripts and per-scenario reveal shims from the
repo and rootfs image, removed extra build/deploy/smoke helpers from the remote
rootfs, and left `use-practice` as the user-facing entrypoint.

## Recommendation

Do the migration incrementally. Replace only the dispatcher first and keep the
scenario scripts unchanged. That gets the terminal reliability and testability
benefits without turning the work into a full rewrite.
