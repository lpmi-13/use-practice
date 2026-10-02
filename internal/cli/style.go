package cli

import (
	"io"
	"os"
	"strings"
	"syscall"
	"unicode/utf8"
)

// The visual system is deliberately small: the 16 basic ANSI colours (so the
// user's terminal theme picks the shades), cyan for menu focus, and red/yellow
// for problems. Colour never carries meaning alone: every styled item keeps
// its word, so output reads the same with colour off.
// Scenario script output is never restyled.

// palette applies styles when colour is on. The zero value is plain output,
// which is what tests and piped output see.
type palette struct {
	color bool
}

// detectColor decides whether to style output. Colour is off for NO_COLOR,
// TERM=dumb, a non-terminal writer, or --no-color, and
// USE_PRACTICE_COLOR=always|never overrides the automatic choice.
func detectColor(getenv func(string) string, tty, noColorFlag bool) bool {
	color := tty && getenv("TERM") != "dumb" && getenv("NO_COLOR") == ""
	switch strings.ToLower(strings.TrimSpace(getenv("USE_PRACTICE_COLOR"))) {
	case "always", "on", "yes", "1":
		color = true
	case "never", "off", "no", "0":
		color = false
	}
	if noColorFlag {
		color = false
	}
	return color
}

// paletteFor returns the palette for output written to w.
func paletteFor(w io.Writer, noColorFlag bool) palette {
	f, ok := w.(*os.File)
	return palette{color: detectColor(os.Getenv, ok && isTerminal(f), noColorFlag)}
}

func (p palette) sgr(code, s string) string {
	if !p.color || s == "" {
		return s
	}
	return "\033[" + code + "m" + s + "\033[0m"
}

func (p palette) bold(s string) string    { return p.sgr("1", s) }
func (p palette) faint(s string) string   { return p.sgr("2", s) }
func (p palette) reverse(s string) string { return p.sgr("7", s) }
func (p palette) accent(s string) string  { return p.sgr("36", s) }
func (p palette) heading(s string) string { return p.sgr("1;36", s) }
func (p palette) bad(s string) string     { return p.sgr("31", s) }
func (p palette) warn(s string) string    { return p.sgr("33", s) }

// visibleWidth counts the terminal columns s occupies, skipping ANSI escape
// sequences and other control bytes.
func visibleWidth(s string) int {
	cols := 0
	for i := 0; i < len(s); {
		if s[i] == 0x1b {
			i = skipEscape(s, i)
			continue
		}
		r, size := utf8.DecodeRuneInString(s[i:])
		i += size
		if r >= 0x20 && r != 0x7f {
			cols++
		}
	}
	return cols
}

// skipEscape returns the index just past the CSI escape sequence starting at
// i, or just past ESC and the following byte for anything else.
func skipEscape(s string, i int) int {
	i++
	if i >= len(s) {
		return i
	}
	if s[i] != '[' {
		return i + 1
	}
	for i++; i < len(s); i++ {
		if s[i] >= 0x40 && s[i] <= 0x7e {
			return i + 1
		}
	}
	return i
}

// padRight pads s with spaces to width visible columns.
func padRight(s string, width int) string {
	if pad := width - visibleWidth(s); pad > 0 {
		return s + strings.Repeat(" ", pad)
	}
	return s
}

func isTerminal(f *os.File) bool {
	var termios syscall.Termios
	return ioctlTermios(int(f.Fd()), syscall.TCGETS, &termios) == nil
}
