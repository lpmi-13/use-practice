package main

import (
	"runtime"
	"runtime/debug"
	"sync/atomic"
	"syscall"
	"time"

	"use-practice/loadgen/internal/cfg"
)

const pageSize = 4096

var memSink atomic.Uint64

// runMem allocates a large resident ballast. The resident profile leaves that
// ballast mostly steady for a utilization-heavy signal; the pressure profile
// adds bounded anonymous mmap churn to force reclaim stalls without intending
// to OOM the host.
func runMem(c *cfg.Config) {
	mb := c.Int("mb", 256)
	if mb < 1 {
		mb = 1
	}
	touch := time.Duration(c.Int("touch_ms", 1000)) * time.Millisecond
	profile := c.Str("profile", "resident")

	buf := allocateResident(mb)

	if profile == "pressure" {
		runMemPressure(c, buf, touch)
		return
	}

	runMemResident(buf, touch)
}

func allocateResident(mb int) []byte {
	buf := make([]byte, mb*1024*1024)
	for i := 0; i < len(buf); i += pageSize {
		buf[i] = 1
	}
	return buf
}

func runMemResident(buf []byte, touch time.Duration) {
	if touch <= 0 {
		touch = 10 * time.Second
	}

	var n byte = 1
	for {
		time.Sleep(touch)
		n++
		// Retouch slowly so the resident set remains attributable without
		// creating continuous reclaim pressure by itself.
		for i := 0; i < len(buf); i += pageSize * 16 {
			buf[i] = n
		}
		memSink.Add(uint64(n))
	}
}

func runMemPressure(c *cfg.Config, ballast []byte, touch time.Duration) {
	churnMB := c.Int("churn_mb", 128)
	if churnMB < 1 {
		churnMB = 1
	}
	burst := time.Duration(c.Int("burst_ms", 750)) * time.Millisecond
	if burst <= 0 {
		burst = 750 * time.Millisecond
	}
	pause := time.Duration(c.Int("pause_ms", 250)) * time.Millisecond
	if pause < 0 {
		pause = 0
	}
	if touch <= 0 {
		touch = time.Second
	}

	var n byte = 1
	nextBallastTouch := time.Now().Add(touch)
	for {
		deadline := time.Now().Add(burst)
		for time.Now().Before(deadline) {
			churnAnonymous(churnMB, n)
			n++
		}

		if time.Now().After(nextBallastTouch) {
			for i := 0; i < len(ballast); i += pageSize * 32 {
				ballast[i] = n
			}
			nextBallastTouch = time.Now().Add(touch)
		}

		if pause > 0 {
			time.Sleep(pause)
		}
	}
}

func churnAnonymous(mb int, seed byte) {
	size := mb * 1024 * 1024
	if size < pageSize {
		size = pageSize
	}

	buf, err := syscall.Mmap(
		-1,
		0,
		size,
		syscall.PROT_READ|syscall.PROT_WRITE,
		syscall.MAP_ANON|syscall.MAP_PRIVATE,
	)
	if err != nil {
		fallbackChurn(size, seed)
		return
	}
	touchAll(buf, seed)
	_ = syscall.Munmap(buf)
}

func fallbackChurn(size int, seed byte) {
	buf := make([]byte, size)
	touchAll(buf, seed)
	runtime.KeepAlive(buf)
	debug.FreeOSMemory()
}

func touchAll(buf []byte, seed byte) {
	var sum uint64
	for i := 0; i < len(buf); i += pageSize {
		v := seed + byte(i/pageSize)
		buf[i] = v
		sum += uint64(v)
	}
	memSink.Store(sum)
}
