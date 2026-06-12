package main

import (
	"io"
	"net"
	"time"

	"use-practice/loadgen/internal/cfg"
)

// runNetServer drains everything it receives on the configured port. It is the
// sink the netclient culprit talks to.
func runNetServer(c *cfg.Config) {
	proto := c.Str("proto", "tcp")
	addr := ":" + c.Str("port", "5201")
	readBPS := c.Int("read_bps", 0)
	readBuf := c.Int("read_buf", 0)

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
		if readBuf > 0 {
			setTCPReadBuffer(conn, readBuf)
		}
		if readBPS > 0 {
			go drainSlow(conn, readBPS)
		} else {
			go io.Copy(io.Discard, conn)
		}
	}
}

// runNetClient opens the configured number of flows to the sink and paces each
// to its share of the offered bandwidth.
func runNetClient(c *cfg.Config) {
	proto := c.Str("proto", "tcp")
	addr := net.JoinHostPort(c.Str("host", "127.0.0.1"), c.Str("port", "5201"))
	mbps := c.Int("mbps", 200)
	parallel := c.Int("parallel", 1)
	writeBuf := c.Int("write_buf", 0)
	if parallel < 1 {
		parallel = 1
	}

	perConn := mbps * 1_000_000 / 8 / parallel // bytes/sec per flow
	for i := 0; i < parallel; i++ {
		go blast(proto, addr, perConn, writeBuf)
	}
	select {}
}

func blast(proto, addr string, bps int, writeBuf int) {
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
		if writeBuf > 0 {
			setTCPWriteBuffer(conn, writeBuf)
		}
		writeRate(conn, buf, bps)
		conn.Close()
	}
}

// writeRate writes buf repeatedly, sleeping between writes to approximate bps
// bytes per second. It returns on the first write error so blast can reconnect.
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

func drainSlow(conn net.Conn, bps int) {
	defer conn.Close()
	if bps < 1 {
		bps = 1
	}
	buf := make([]byte, 4096)
	chunksPerSec := bps / len(buf)
	if chunksPerSec < 1 {
		chunksPerSec = 1
	}
	interval := time.Second / time.Duration(chunksPerSec)
	for {
		if _, err := conn.Read(buf); err != nil {
			return
		}
		time.Sleep(interval)
	}
}

func setTCPReadBuffer(conn net.Conn, bytes int) {
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.SetReadBuffer(bytes)
	}
}

func setTCPWriteBuffer(conn net.Conn, bytes int) {
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.SetWriteBuffer(bytes)
		_ = tcp.SetNoDelay(true)
	}
}

func fatalRetry() {
	time.Sleep(time.Second)
	panic("uworker: could not bind listener")
}
