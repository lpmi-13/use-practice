package main

import (
	"net"
	"os"
	"sync/atomic"
	"time"

	"use-practice/loadgen/internal/cfg"
)

// bsink keeps the heartbeat loop from being optimised away.
var bsink atomic.Uint64

// runBaseline emulates a low-activity service: a small held resident set, a
// sub-1% CPU tick, occasional tiny disk I/O, and occasional tiny UDP traffic.
// It never dominates any resource — its job is to be plausible background noise
// the culprit has to be picked out from.
func runBaseline(c *cfg.Config) {
	baseMB := c.Int("base_mb", 16)
	if baseMB < 1 {
		baseMB = 1
	}
	scratch := c.Str("scratch", "")
	blip := net.JoinHostPort(c.Str("blip_host", "127.0.0.1"), c.Str("blip_port", "9"))

	// Hold a modest resident set (make() faults the pages in).
	buf := make([]byte, baseMB*1024*1024)
	for i := 0; i < len(buf); i += pageSize {
		buf[i] = 1
	}

	go cpuHeartbeat()
	if scratch != "" {
		go diskHeartbeat(scratch)
	}
	go netHeartbeat(blip)

	// Keep the process (and its resident set) alive.
	for {
		time.Sleep(time.Second)
		buf[0]++
	}
}

func cpuHeartbeat() {
	var x uint64 = 1
	for {
		for i := 0; i < 200_000; i++ {
			x ^= x << 13
			x ^= x >> 7
			x ^= x << 17
		}
		bsink.Store(x)
		time.Sleep(200 * time.Millisecond)
	}
}

func diskHeartbeat(path string) {
	b := make([]byte, 8192)
	for {
		time.Sleep(3 * time.Second)
		if f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0644); err == nil {
			f.Write(b)
			f.Sync()
			f.Close()
		}
		if f, err := os.Open(path); err == nil {
			f.Read(b)
			f.Close()
		}
	}
}

func netHeartbeat(addr string) {
	msg := make([]byte, 64)
	for {
		time.Sleep(2 * time.Second)
		if conn, err := net.Dial("udp", addr); err == nil {
			conn.Write(msg)
			conn.Close()
		}
	}
}
