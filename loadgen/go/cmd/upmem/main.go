// upmem allocates a large buffer, faults every page in, and keeps the pages
// resident by periodically re-touching them. The result is a steady, oversized
// resident set: memory utilization climbs and, on hosts without much RAM,
// swap/PSI pressure follows.
package main

import (
	"time"

	"use-practice/loadgen/internal/cfg"
)

const pageSize = 4096

func main() {
	c := cfg.Load()
	mb := c.Int("mb", 256)
	if mb < 1 {
		mb = 1
	}
	touch := time.Duration(c.Int("touch_ms", 1000)) * time.Millisecond

	// make() zeroes the slice, which faults the pages in immediately.
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
