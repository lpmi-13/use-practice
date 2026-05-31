// upcpu pins one or more workers to a tight arithmetic loop, holding the
// configured number of cores at ~100% user time and pushing up the run queue.
package main

import (
	"runtime"
	"sync/atomic"

	"use-practice/loadgen/internal/cfg"
)

// sink keeps the compiler from optimising the loop body away.
var sink atomic.Uint64

func main() {
	c := cfg.Load()
	workers := c.Int("workers", 2)
	if workers < 1 {
		workers = 1
	}

	runtime.GOMAXPROCS(workers)
	for i := 0; i < workers; i++ {
		go burn(uint64(i)*2654435761 + 1)
	}
	select {} // run until the process is killed
}

func burn(seed uint64) {
	runtime.LockOSThread()
	x := seed | 1
	var acc uint64
	for {
		for i := 0; i < 1<<16; i++ {
			x ^= x << 13
			x ^= x >> 7
			x ^= x << 17
			acc += x * x
		}
		sink.Store(acc)
	}
}
