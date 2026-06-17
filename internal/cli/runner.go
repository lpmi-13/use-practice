package cli

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"syscall"
)

type Command struct {
	Path   string
	Args   []string
	Dir    string
	Env    []string
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
}

type Runner interface {
	Run(Command) error
}

type ExecRunner struct{}

func (ExecRunner) Run(c Command) error {
	cmd := exec.Command(c.Path, c.Args...)
	cmd.Dir = c.Dir
	cmd.Env = c.Env
	cmd.Stdin = c.Stdin
	cmd.Stdout = c.Stdout
	cmd.Stderr = c.Stderr
	return cmd.Run()
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return 1
}

func pidAlive(pid string) bool {
	var parsed int
	for _, r := range pid {
		if r < '0' || r > '9' {
			return false
		}
		parsed = parsed*10 + int(r-'0')
	}
	if parsed <= 0 {
		return false
	}
	return syscall.Kill(parsed, 0) == nil
}

func commandEnv(extra ...string) []string {
	env := os.Environ()
	return append(env, extra...)
}
