// uworker is the generic Go workload. Every service in a CPU, memory, or
// network scenario runs this same binary; a config file picks its behavior.
// One service per scenario runs the active load profile (cpu/mem/netclient,
// plus a netserver sink for network); the rest run "baseline", a small
// multi-resource heartbeat that makes them look like real, lightly-loaded
// services rather than idle placeholders.
package main

import "use-practice/loadgen/internal/cfg"

func main() {
	c := cfg.Load()
	switch c.Str("mode", "baseline") {
	case "cpu":
		runCPU(c)
	case "mem":
		runMem(c)
	case "netserver":
		runNetServer(c)
	case "netclient":
		runNetClient(c)
	default:
		runBaseline(c)
	}
}
