// upnet drives sustained traffic between a sink (server) and a source
// (client). The server drains everything it receives; the client opens the
// configured number of flows and paces each one to its share of the offered
// bandwidth. The kernel's interface and socket counters report the load the
// same way they would for any real service.
package main

import (
	"io"
	"net"
	"time"

	"use-practice/loadgen/internal/cfg"
)

func main() {
	c := cfg.Load()
	role := c.Str("role", "server")
	proto := c.Str("proto", "tcp")
	port := c.Str("port", "5201")

	if role == "server" {
		runServer(proto, ":"+port)
		return
	}

	host := c.Str("host", "127.0.0.1")
	mbps := c.Int("mbps", 200)
	parallel := c.Int("parallel", 1)
	if parallel < 1 {
		parallel = 1
	}
	runClient(proto, net.JoinHostPort(host, port), mbps, parallel)
}

func runServer(proto, addr string) {
	if proto == "udp" {
		pc, err := net.ListenPacket("udp", addr)
		if err != nil {
			fatalRetry()
		}
		buf := make([]byte, 65536)
		for {
			if _, _, err := pc.ReadFrom(buf); err != nil {
				return
			}
		}
	}

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fatalRetry()
	}
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go io.Copy(io.Discard, conn)
	}
}

func runClient(proto, addr string, mbps, parallel int) {
	perConn := mbps * 1_000_000 / 8 / parallel // bytes/sec per flow
	for i := 0; i < parallel; i++ {
		go blast(proto, addr, perConn)
	}
	select {}
}

func blast(proto, addr string, bps int) {
	chunk := 65536
	if proto == "udp" {
		chunk = 1400
	}
	buf := make([]byte, chunk)

	for {
		conn, err := net.Dial(proto, addr)
		if err != nil {
			time.Sleep(time.Second)
			continue
		}
		writeRate(conn, buf, bps)
		conn.Close()
	}
}

// writeRate writes buf repeatedly, sleeping between writes to approximate bps
// bytes per second. It returns on the first write error so the caller can
// reconnect.
func writeRate(conn net.Conn, buf []byte, bps int) {
	if bps < 1 {
		bps = 1
	}
	chunksPerSec := bps / len(buf)
	if chunksPerSec < 1 {
		chunksPerSec = 1
	}
	interval := time.Second / time.Duration(chunksPerSec)
	for {
		if _, err := conn.Write(buf); err != nil {
			return
		}
		time.Sleep(interval)
	}
}

func fatalRetry() {
	// Give the supervising script a moment, then exit non-zero so the failure
	// is visible in the recorded process state.
	time.Sleep(time.Second)
	panic("upnet: could not bind listener")
}
