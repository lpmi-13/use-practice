package main

import (
	"time"

	"use-practice/loadgen/internal/cfg"
)

const pageSize = 4096

// runMem allocates a large buffer, faults every page in, and keeps the pages
// resident by periodically re-touching them: a steady oversized resident set
// that drives memory utilization and, on small hosts, swap/PSI pressure.
func runMem(c *cfg.Config) {
	mb := c.Int("mb", 256)
	if mb < 1 {
		mb = 1
	}
	touch := time.Duration(c.Int("touch_ms", 1000)) * time.Millisecond

	buf := make([]byte, mb*1024*1024)
	for i := 0; i < len(buf); i += pageSize {
		buf[i] = 1
	}

	var n byte = 1
	for {
		time.Sleep(touch)
		n++
		for i := 0; i < len(buf); i += pageSize {
			buf[i] = n
		}
	}
}
