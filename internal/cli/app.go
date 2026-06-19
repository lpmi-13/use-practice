package cli

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type App struct {
	Root      string
	StateRoot string
	In        io.Reader
	Out       io.Writer
	Err       io.Writer
	Runner    Runner
	Selector  SelectorFunc
	Random    *rand.Rand
	PIDAlive  func(string) bool
}

func NewApp() *App {
	return &App{
		In:       os.Stdin,
		Out:      os.Stdout,
		Err:      os.Stderr,
		Runner:   ExecRunner{},
		Selector: terminalSelector,
		Random:   rand.New(rand.NewSource(time.Now().UnixNano())),
		PIDAlive: pidAlive,
	}
}

func (a *App) Run(args []string) int {
	a.setDefaults()
	if a.Root == "" {
		root, err := resolveRoot()
		if err != nil {
			fmt.Fprintf(a.Err, "error: %v\n", err)
			return 1
		}
		a.Root = root
	}
	if a.StateRoot == "" {
		a.StateRoot = resolveStateRoot(a.Root)
	}

	if len(args) == 0 {
		cmd, err := a.selectValue(SelectorSpec{
			Title:    "use-practice - choose a command",
			Options:  SubcommandOptions(),
			Fallback: "run",
		})
		if err != nil {
			if errors.Is(err, ErrSelectorQuit) {
				return 130
			}
			fmt.Fprintf(a.Err, "error: %v\n", err)
			return 1
		}
		return a.runCommand(cmd, nil)
	}

	cmd := args[0]
	rest := args[1:]
	if IsResourceOrRandom(cmd) {
		return a.runScenario(cmd)
	}
	return a.runCommand(cmd, rest)
}

func (a *App) setDefaults() {
	if a.In == nil {
		a.In = os.Stdin
	}
	if a.Out == nil {
		a.Out = os.Stdout
	}
	if a.Err == nil {
		a.Err = os.Stderr
	}
	if a.Runner == nil {
		a.Runner = ExecRunner{}
	}
	if a.Selector == nil {
		a.Selector = terminalSelector
	}
	if a.Random == nil {
		a.Random = rand.New(rand.NewSource(time.Now().UnixNano()))
	}
	if a.PIDAlive == nil {
		a.PIDAlive = pidAlive
	}
}

func (a *App) runCommand(cmd string, args []string) int {
	switch cmd {
	case "run":
		if len(args) > 1 {
			a.usage()
			return 1
		}
		if len(args) == 0 {
			return a.runScenario("")
		}
		return a.runScenario(args[0])
	case "reveal":
		return a.reveal()
	case "stop":
		return a.stopAll(false)
	case "list":
		a.list()
		return 0
	case "status":
		return a.status()
	case "-h", "--help", "help":
		a.usage()
		return 0
	default:
		a.usage()
		return 1
	}
}

func (a *App) runScenario(mode string) int {
	if mode == "-h" || mode == "--help" || mode == "help" {
		a.usage()
		return 0
	}
	if mode == "" {
		selected, err := a.selectValue(SelectorSpec{
			Title:    "Resource scenario - choose what to run",
			Options:  ResourceOptions(),
			Fallback: "random",
		})
		if err != nil {
			if errors.Is(err, ErrSelectorQuit) {
				return 130
			}
			fmt.Fprintf(a.Err, "error: %v\n", err)
			return 1
		}
		mode = selected
	}
	if !IsResourceOrRandom(mode) {
		a.usage()
		return 1
	}

	if mode == "random" {
		pick := a.randomResource()
		a.stopAll(true)
		if err := a.runStartScript(pick, "", true); err != nil {
			return exitCode(err)
		}
		a.blindBanner()
		return 0
	}

	profile, err := a.selectValue(SelectorSpec{
		Title:    fmt.Sprintf("%s profile - choose what to run", mode),
		Options:  ProfileOptions(mode),
		Fallback: "random",
	})
	if err != nil {
		if errors.Is(err, ErrSelectorQuit) {
			return 130
		}
		fmt.Fprintf(a.Err, "error: %v\n", err)
		return 1
	}

	a.stopAll(true)
	fmt.Fprintf(a.Out, "==> Running scenario: %s\n", mode)
	if err := a.runStartScript(mode, profile, false); err != nil {
		return exitCode(err)
	}
	return 0
}

func (a *App) selectValue(spec SelectorSpec) (string, error) {
	if a.Selector == nil {
		return spec.Fallback, nil
	}
	return a.Selector(spec)
}

func (a *App) runStartScript(resource string, profile string, blind bool) error {
	path := filepath.Join(a.Root, "scenarios", resource, "start.sh")
	cmd := Command{
		Path:   path,
		Dir:    a.Root,
		Env:    commandEnv(a.envOverrides()...),
		Stdin:  a.In,
		Stdout: a.Out,
		Stderr: a.Err,
	}
	if blind {
		cmd.Dir = filepath.Join(a.Root, "scenarios", resource)
		cmd.Stdout = io.Discard
	} else if envName := ProfileEnvVar(resource); envName != "" {
		cmd.Env = commandEnv(append(a.envOverrides(), envName+"="+profile)...)
	}
	return a.Runner.Run(cmd)
}

func (a *App) stopAll(quiet bool) int {
	for _, resource := range scenarioResources {
		path := filepath.Join(a.Root, "scenarios", resource, "stop.sh")
		cmd := Command{
			Path:   path,
			Dir:    filepath.Join(a.Root, "scenarios", resource),
			Env:    commandEnv(a.envOverrides()...),
			Stdin:  a.In,
			Stdout: a.Out,
			Stderr: a.Err,
		}
		if quiet {
			cmd.Stdout = io.Discard
			cmd.Stderr = io.Discard
		}
		_ = a.Runner.Run(cmd)
	}
	return 0
}

func (a *App) reveal() int {
	pick, ok := a.activeScenario()
	if !ok {
		fmt.Fprintln(a.Out, "No active scenario. Start one with use-practice run")
		return 1
	}
	for _, base := range a.scenarioStateBases(pick) {
		answerPath := filepath.Join(base, ".answer")
		data, err := os.ReadFile(answerPath)
		if err == nil {
			_, _ = a.Out.Write(data)
			return 0
		}
	}
	fmt.Fprintf(a.Out, "Scenario '%s' has no answer file. Was it started?\n", pick)
	return 1
}

func (a *App) status() int {
	pick, ok := a.activeScenario()
	if !ok {
		fmt.Fprintln(a.Out, "No active scenario.")
		return 0
	}

	runID := ""
	for _, base := range a.scenarioStateBases(pick) {
		if data, err := os.ReadFile(filepath.Join(base, ".run-id")); err == nil {
			runID = strings.TrimSpace(string(data))
			break
		}
	}
	if runID == "" {
		fmt.Fprintln(a.Out, "Active run: unknown")
	} else {
		fmt.Fprintf(a.Out, "Active run: %s\n", runID)
	}

	for _, base := range a.scenarioStateBases(pick) {
		processPath := filepath.Join(base, ".processes")
		if _, err := os.Stat(processPath); err == nil {
			a.printRecordedProcesses(processPath)
			break
		}
	}
	return 0
}

func (a *App) activeScenario() (string, bool) {
	for _, resource := range scenarioResources {
		for _, base := range a.scenarioStateBases(resource) {
			if fileExists(filepath.Join(base, ".run-id")) || fileExists(filepath.Join(base, ".answer")) {
				return resource, true
			}
		}
	}
	return "", false
}

func (a *App) printRecordedProcesses(path string) {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(a.Out, "No recorded workload processes.")
		return
	}
	defer f.Close()

	fmt.Fprintf(a.Out, "%-8s %-18s %-10s\n", "PID", "SERVICE", "STATE")
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 || fields[0] == "" {
			continue
		}
		state := "exited"
		if a.PIDAlive(fields[0]) {
			state = "running"
		}
		fmt.Fprintf(a.Out, "%-8s %-18s %-10s\n", fields[0], fields[1], state)
	}
}

func (a *App) list() {
	for _, option := range ResourceOptions() {
		fmt.Fprintf(a.Out, "%-16s%s\n", option.Label, option.Summary)
	}
}

func (a *App) usage() {
	fmt.Fprint(a.Out, `Usage:
  use-practice
  use-practice run [scenario|random]
  use-practice reveal
  use-practice stop
  use-practice list
  use-practice status

Scenarios:
  random cpu memory disk network
`)
}

func (a *App) blindBanner() {
	fmt.Fprint(a.Out, `==> Blind scenario started. The resource type is hidden.

Walk the USE method across every resource:
  CPU:     top  /  vmstat 1  /  mpstat -P ALL 1
  Memory:  free -m  /  vmstat 1 (si/so)  /  cat /proc/pressure/memory
  Disk:    iostat -xz 1  /  pidstat -d 1
  Network: sar -n DEV 1  /  ss -s  /  ip -s link

Companion CLI:
  use-tool practice system

Process/service attribution:
  use-practice status
  top -bcn1 w512
  top -H -bcn1 w512
  ps -eo pid,ppid,pgid,stat,pcpu,pmem,args --sort=-pcpu | head
  ps -eLo pid,tid,stat,wchan,comm | awk '$3 ~ /R|D/'
  pidstat 1

When you have an answer:
  use-practice reveal
  use-practice stop
`)
}

func (a *App) randomResource() string {
	return scenarioResources[a.Random.Intn(len(scenarioResources))]
}

func resolveRoot() (string, error) {
	if envRoot := os.Getenv("USE_PRACTICE_ROOT"); envRoot != "" {
		return filepath.Abs(envRoot)
	}
	if cwd, err := os.Getwd(); err == nil && fileExists(filepath.Join(cwd, "scenarios")) {
		return cwd, nil
	}
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Dir(exe), nil
}

func resolveStateRoot(root string) string {
	if envRoot := os.Getenv("USE_PRACTICE_STATE_DIR"); envRoot != "" {
		abs, err := filepath.Abs(envRoot)
		if err != nil {
			return envRoot
		}
		return abs
	}

	cleanRoot := filepath.Clean(root)
	if resolved, err := filepath.EvalSymlinks(cleanRoot); err == nil {
		cleanRoot = resolved
	}
	if cleanRoot == "/opt/use-practice" {
		return "/var/lib/use-practice/state"
	}
	return ""
}

func (a *App) envOverrides() []string {
	overrides := []string{"USE_PRACTICE_ROOT=" + a.Root}
	if a.StateRoot != "" {
		overrides = append(overrides, "USE_PRACTICE_STATE_DIR="+a.StateRoot)
	}
	return overrides
}

func (a *App) scenarioStateBases(resource string) []string {
	legacy := filepath.Join(a.Root, "scenarios", resource)
	if a.StateRoot == "" {
		return []string{legacy}
	}
	current := filepath.Join(a.StateRoot, resource)
	if current == legacy {
		return []string{current}
	}
	return []string{current, legacy}
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
