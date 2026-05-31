package main

import (
	"math/rand"
	"net"
	"os"
	"sync/atomic"
	"time"

	"use-practice/loadgen/internal/cfg"
)

// bsink keeps the heartbeat loop from being optimised away.
var bsink atomic.Uint64

// runBaseline emulates a low-activity production service: it touches all four
// resources at a tiny rate — a small held resident set (memory), a sub-1% CPU
// tick, occasional small disk I/O, and occasional tiny UDP traffic. Each decoy
// seeds its rhythm from its PID so the fleet doesn't blip in lockstep.
func runBaseline(c *cfg.Config) {
	baseMB := c.Int("base_mb", 16)
	if baseMB < 1 {
		baseMB = 1
	}
	scratch := c.Str("scratch", "")
	blip := net.JoinHostPort(c.Str("blip_host", "127.0.0.1"), c.Str("blip_port", "9"))

	seed := int64(os.Getpid())

	// Hold a modest resident set (make() faults the pages in).
	buf := make([]byte, baseMB*1024*1024)
	for i := 0; i < len(buf); i += pageSize {
		buf[i] = 1
	}

	go cpuHeartbeat(seed)
	if scratch != "" {
		go diskHeartbeat(scratch, seed+1)
	}
	go netHeartbeat(blip, seed+2)

	// Keep the process (and its resident set) alive.
	for {
		time.Sleep(time.Second)
		buf[0]++
	}
}

func cpuHeartbeat(seed int64) {
	rng := rand.New(rand.NewSource(seed))
	var x uint64 = 1
	for {
		n := 120_000 + rng.Intn(160_000) // small, varied burst (<1%)
		for i := 0; i < n; i++ {
			x ^= x << 13
			x ^= x >> 7
			x ^= x << 17
		}
		bsink.Store(x)
		time.Sleep(time.Duration(150+rng.Intn(150)) * time.Millisecond)
	}
}

func diskHeartbeat(path string, seed int64) {
	rng := rand.New(rand.NewSource(seed))
	b := make([]byte, 8192)
	for {
		time.Sleep(time.Duration(2000+rng.Intn(4000)) * time.Millisecond)
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

func netHeartbeat(addr string, seed int64) {
	rng := rand.New(rand.NewSource(seed))
	msg := make([]byte, 64)
	for {
		time.Sleep(time.Duration(1500+rng.Intn(3000)) * time.Millisecond)
		if conn, err := net.Dial("udp", addr); err == nil {
			conn.Write(msg)
			conn.Close()
		}
	}
}
