package cli

import (
	"bytes"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

type recordingRunner struct {
	commands []Command
	fail     error
}

func (r *recordingRunner) Run(c Command) error {
	r.commands = append(r.commands, c)
	return r.fail
}

func newTestApp(t *testing.T, selections ...string) (*App, *recordingRunner, *bytes.Buffer) {
	t.Helper()

	out := &bytes.Buffer{}
	runner := &recordingRunner{}
	i := 0
	app := &App{
		Root:   t.TempDir(),
		In:     strings.NewReader(""),
		Out:    out,
		Err:    out,
		Runner: runner,
		Random: rand.New(rand.NewSource(1)),
		PIDAlive: func(pid string) bool {
			return pid == "123"
		},
		Selector: func(spec SelectorSpec) (string, error) {
			if i >= len(selections) {
				return spec.Fallback, nil
			}
			selection := selections[i]
			i++
			return selection, nil
		},
	}
	createScenarioDirs(t, app.Root)
	return app, runner, out
}

func createScenarioDirs(t *testing.T, root string) {
	t.Helper()
	for _, resource := range scenarioResources {
		dir := filepath.Join(root, "scenarios", resource)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
}

func TestBareCommandUsesSubcommandSelector(t *testing.T) {
	app, runner, out := newTestApp(t, "list")

	if code := app.Run(nil); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	if len(runner.commands) != 0 {
		t.Fatalf("list should not shell out, got %d commands", len(runner.commands))
	}
	if !strings.Contains(out.String(), "random") || !strings.Contains(out.String(), "network") {
		t.Fatalf("list output missing resources:\n%s", out.String())
	}
}

func TestBareCommandFallsBackToRunRandom(t *testing.T) {
	app, runner, out := newTestApp(t)

	if code := app.Run(nil); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	if got := len(runner.commands); got != 5 {
		t.Fatalf("expected 4 quiet stops and 1 start, got %d", got)
	}
	start := runner.commands[4]
	if filepath.Base(start.Path) != "start.sh" {
		t.Fatalf("expected start.sh, got %#v", start)
	}
	if start.Stdout != io.Discard {
		t.Fatalf("blind random start stdout should be discarded")
	}
	if strings.Contains(strings.Join(start.Env, "\n"), "_PROFILE=") {
		t.Fatalf("blind random start should not set resource profile env: %#v", start.Env)
	}
	if !strings.Contains(out.String(), "==> Blind scenario started") {
		t.Fatalf("blind banner missing:\n%s", out.String())
	}
}

func TestRunRandomAliasStartsBlindScenario(t *testing.T) {
	app, runner, out := newTestApp(t)

	if code := app.Run([]string{"random"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	if got := len(runner.commands); got != 5 {
		t.Fatalf("expected 4 quiet stops and 1 start, got %d", got)
	}
	start := runner.commands[4]
	if start.Stdout != io.Discard {
		t.Fatalf("blind random start stdout should be discarded")
	}
	if !strings.Contains(out.String(), "==> Blind scenario started") {
		t.Fatalf("blind banner missing:\n%s", out.String())
	}
}

func TestRunResourceSelectsProfileAndSetsEnvironment(t *testing.T) {
	app, runner, out := newTestApp(t, "oom")

	if code := app.Run([]string{"run", "memory"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	if got := len(runner.commands); got != 5 {
		t.Fatalf("expected 4 quiet stops and 1 start, got %d", got)
	}
	start := runner.commands[4]
	if !strings.HasSuffix(start.Path, filepath.Join("scenarios", "memory", "start.sh")) {
		t.Fatalf("wrong start script: %s", start.Path)
	}
	if !envContains(start.Env, "MEM_PROFILE=oom") {
		t.Fatalf("missing MEM_PROFILE=oom in env: %#v", start.Env)
	}
	if start.Stdout == io.Discard {
		t.Fatalf("explicit resource start should stream stdout")
	}
	if !strings.Contains(out.String(), "==> Running scenario: memory") {
		t.Fatalf("explicit run banner missing:\n%s", out.String())
	}
}

func TestDirectResourceAliasUsesProfileSelector(t *testing.T) {
	app, runner, _ := newTestApp(t, "kernelwait")

	if code := app.Run([]string{"cpu"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	start := runner.commands[len(runner.commands)-1]
	if !strings.HasSuffix(start.Path, filepath.Join("scenarios", "cpu", "start.sh")) {
		t.Fatalf("wrong start script: %s", start.Path)
	}
	if !envContains(start.Env, "CPU_PROFILE=kernelwait") {
		t.Fatalf("missing CPU_PROFILE=kernelwait in env: %#v", start.Env)
	}
}

func TestRunSelectorCanChooseResource(t *testing.T) {
	app, runner, _ := newTestApp(t, "disk", "saturation")

	if code := app.Run([]string{"run"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	start := runner.commands[len(runner.commands)-1]
	if !strings.HasSuffix(start.Path, filepath.Join("scenarios", "disk", "start.sh")) {
		t.Fatalf("wrong start script: %s", start.Path)
	}
	if !envContains(start.Env, "DISK_PROFILE=saturation") {
		t.Fatalf("missing DISK_PROFILE=saturation in env: %#v", start.Env)
	}
}

func TestStopRunsEveryScenarioStopScript(t *testing.T) {
	app, runner, _ := newTestApp(t)

	if code := app.Run([]string{"stop"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	if got := len(runner.commands); got != len(scenarioResources) {
		t.Fatalf("expected %d stop commands, got %d", len(scenarioResources), got)
	}
	for i, resource := range scenarioResources {
		cmd := runner.commands[i]
		if !strings.HasSuffix(cmd.Path, filepath.Join("scenarios", resource, "stop.sh")) {
			t.Fatalf("wrong stop command %d: %s", i, cmd.Path)
		}
		if cmd.Stdout == io.Discard {
			t.Fatalf("explicit stop should not discard stdout")
		}
	}
}

func TestStatusPrintsOnlyPidServiceState(t *testing.T) {
	app, _, out := newTestApp(t)
	scenarioDir := filepath.Join(app.Root, "scenarios", "memory")
	if err := os.WriteFile(filepath.Join(scenarioDir, ".run-id"), []byte("r1234\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	processes := strings.Join([]string{
		"123\tcheckout\tmemory worker holding 1024 MB\tscenarios/memory/.logs/checkout.log",
		"456\tqueue\tservice queue (baseline)\tscenarios/memory/.logs/queue.log",
	}, "\n")
	if err := os.WriteFile(filepath.Join(scenarioDir, ".processes"), []byte(processes), 0o644); err != nil {
		t.Fatal(err)
	}

	if code := app.Run([]string{"status"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}

	got := out.String()
	if !strings.Contains(got, "Active run: r1234") {
		t.Fatalf("missing run id:\n%s", got)
	}
	if !strings.Contains(got, "123      checkout") || !strings.Contains(got, "running") {
		t.Fatalf("missing running process row:\n%s", got)
	}
	for _, leaked := range []string{"memory worker", "baseline", ".logs", "1024"} {
		if strings.Contains(got, leaked) {
			t.Fatalf("status leaked %q:\n%s", leaked, got)
		}
	}
}

func TestRevealPrintsAnswerVerbatim(t *testing.T) {
	app, _, out := newTestApp(t)
	scenarioDir := filepath.Join(app.Root, "scenarios", "cpu")
	if err := os.WriteFile(filepath.Join(scenarioDir, ".answer"), []byte("Resource: CPU\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if code := app.Run([]string{"reveal"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}
	if got := out.String(); got != "Resource: CPU\n" {
		t.Fatalf("unexpected reveal output %q", got)
	}
}

func TestExecRunnerLaunchesScenarioScriptsWithEnvironment(t *testing.T) {
	root := t.TempDir()
	createScenarioDirs(t, root)

	for _, resource := range scenarioResources {
		stopScript := filepath.Join(root, "scenarios", resource, "stop.sh")
		if err := os.WriteFile(stopScript, []byte(`#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$PWD")" >> ../../stops.log
`), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	startScript := filepath.Join(root, "scenarios", "memory", "start.sh")
	if err := os.WriteFile(startScript, []byte(`#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
{
  printf 'pwd=%s\n' "$(basename "$PWD")"
  printf 'profile=%s\n' "${MEM_PROFILE:-}"
} > ../../start.log
`), 0o755); err != nil {
		t.Fatal(err)
	}

	var out bytes.Buffer
	app := &App{
		Root:     root,
		In:       strings.NewReader(""),
		Out:      &out,
		Err:      &out,
		Runner:   ExecRunner{},
		Selector: func(SelectorSpec) (string, error) { return "oom", nil },
		Random:   rand.New(rand.NewSource(1)),
	}

	if code := app.Run([]string{"run", "memory"}); code != 0 {
		t.Fatalf("Run returned %d; output:\n%s", code, out.String())
	}

	startLog, err := os.ReadFile(filepath.Join(root, "start.log"))
	if err != nil {
		t.Fatal(err)
	}
	if got := string(startLog); got != "pwd=memory\nprofile=oom\n" {
		t.Fatalf("unexpected start log:\n%s", got)
	}

	stopLog, err := os.ReadFile(filepath.Join(root, "stops.log"))
	if err != nil {
		t.Fatal(err)
	}
	stops := strings.Fields(string(stopLog))
	sort.Strings(stops)
	if got := strings.Join(stops, " "); got != "cpu disk memory network" {
		t.Fatalf("unexpected stop order/content: %q", got)
	}
}

func envContains(env []string, wanted string) bool {
	for _, entry := range env {
		if entry == wanted {
			return true
		}
	}
	return false
}
