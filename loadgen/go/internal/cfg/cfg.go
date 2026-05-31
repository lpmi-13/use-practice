// Package cfg loads a workload's parameters from a small key=value file.
//
// The file lives next to the running executable (<exe-dir>/<exe-name>.cfg) so
// that nothing about the workload has to ride on the command line. After the
// values are read the file is unlinked, leaving no on-disk hint behind.
package cfg

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Config is an immutable view of the parsed key=value pairs.
type Config struct{ m map[string]string }

// Load reads the config adjacent to the executable (or $UP_CFG when set),
// removes the file, and returns the parsed values. A missing file yields an
// empty Config so callers fall back to their defaults.
func Load() *Config {
	path := os.Getenv("UP_CFG")
	if path == "" {
		if exe, err := os.Executable(); err == nil {
			path = filepath.Join(filepath.Dir(exe), filepath.Base(exe)+".cfg")
		}
	}

	c := &Config{m: map[string]string{}}
	f, err := os.Open(path)
	if err != nil {
		return c
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if i := strings.IndexByte(line, '='); i >= 0 {
			c.m[strings.TrimSpace(line[:i])] = strings.TrimSpace(line[i+1:])
		}
	}
	f.Close()
	os.Remove(path)
	return c
}

// Str returns the value for k, or def when unset or empty.
func (c *Config) Str(k, def string) string {
	if v, ok := c.m[k]; ok && v != "" {
		return v
	}
	return def
}

// Int returns the value for k parsed as an int, or def when unset/invalid.
func (c *Config) Int(k string, def int) int {
	if v, ok := c.m[k]; ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
