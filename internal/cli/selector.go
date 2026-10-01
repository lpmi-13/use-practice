package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

var ErrSelectorQuit = errors.New("selector quit")

type SelectorSpec struct {
	Title    string
	Options  []Option
	Fallback string
	// NoColor turns styling off, as --no-color does for the rest of the CLI.
	NoColor bool
}

type SelectorFunc func(SelectorSpec) (string, error)

// terminalSelector draws the options below the cursor and redraws them in
// place as the selection moves, so whatever was on screen before (such as
// the previous scenario's banner) stays visible. Ctrl-L clears the screen and
// redraws.
func terminalSelector(spec SelectorSpec) (string, error) {
	if len(spec.Options) == 0 {
		return spec.Fallback, nil
	}
	if !stdinIsTerminal() {
		return spec.Fallback, nil
	}

	out, closeOut := selectorOutput()
	defer closeOut()

	restore, err := enableRawMode(int(os.Stdin.Fd()))
	if err != nil {
		return spec.Fallback, nil
	}
	defer restore()

	p := palette{color: detectColor(os.Getenv, isTerminal(out), spec.NoColor)}
	selected := 0
	showHelp := false
	render := func() int {
		return renderSelector(out, p, terminalWidth(out), spec.Title, spec.Options, selected, showHelp)
	}
	rows := render()
	redraw := func() {
		clearRenderedRows(out, rows)
		rows = render()
	}

	for {
		key, err := readSelectorKey(os.Stdin)
		if err != nil {
			fmt.Fprintln(out)
			return "", err
		}
		switch key {
		case "up":
			selected = (selected + len(spec.Options) - 1) % len(spec.Options)
			redraw()
		case "down":
			selected = (selected + 1) % len(spec.Options)
			redraw()
		case "help":
			showHelp = !showHelp
			redraw()
		case "redraw":
			fmt.Fprint(out, "\033[H\033[2J")
			rows = render()
		case "enter":
			fmt.Fprintln(out)
			return spec.Options[selected].Value, nil
		case "quit":
			fmt.Fprintln(out)
			return "", ErrSelectorQuit
		default:
			if len(key) > 6 && key[:6] == "digit:" {
				digit := int(key[6] - '0')
				if digit >= 1 && digit <= len(spec.Options) {
					selected = digit - 1
					redraw()
				} else {
					fmt.Fprint(out, "\a")
				}
			} else {
				fmt.Fprint(out, "\a")
			}
		}
	}
}

// renderSelector draws the selector starting at the cursor and returns how
// many terminal rows it occupies. The last line has no trailing newline, so
// the cursor stays on it and clearRenderedRows can erase upwards from there.
func renderSelector(w io.Writer, p palette, width int, title string, options []Option, selected int, showHelp bool) int {
	lines := []string{p.bold(title)}
	for i, option := range options {
		row := fmt.Sprintf("%d. %-12s", i+1, option.Label)
		if i == selected {
			row = "> " + p.reverse(row)
		} else {
			row = "  " + row
		}
		lines = append(lines, row+" "+option.Summary)
	}
	lines = append(lines, selectorHelp(p, len(options), showHelp)...)

	rows := 0
	for i, line := range lines {
		if i > 0 {
			fmt.Fprintln(w)
		}
		fmt.Fprint(w, line)
		rows += visualRows(line, width)
	}
	return rows
}

type helpKey struct {
	Key, Desc string
}

func selectorHelp(p palette, optionCount int, showHelp bool) []string {
	jump := fmt.Sprintf("1-%d", optionCount)
	if !showHelp {
		keys := []helpKey{{"↑/k ↓/j", "move"}, {jump, "jump"}, {"Enter", "choose"}, {"q", "quit"}, {"?", "help"}}
		parts := make([]string, len(keys))
		for i, k := range keys {
			parts[i] = k.Key + " " + p.faint(k.Desc)
		}
		return []string{strings.Join(parts, " | ")}
	}
	keys := []helpKey{
		{"↑/k, ↓/j", "move between options"},
		{jump, "jump to an option"},
		{"Enter", "choose the highlighted option"},
		{"q", "quit"},
		{"?", "hide help"},
	}
	width := 0
	for _, k := range keys {
		width = max(width, visibleWidth(k.Key))
	}
	lines := []string{"Keys:"}
	for _, k := range keys {
		lines = append(lines, "  "+padRight(k.Key, width)+"  "+p.faint(k.Desc))
	}
	return lines
}

// visualRows is how many terminal rows line takes up once it wraps.
func visualRows(line string, width int) int {
	if width <= 0 {
		width = 80
	}
	cols := visibleWidth(line)
	if cols == 0 {
		return 1
	}
	return (cols + width - 1) / width
}

// clearRenderedRows erases the rows a previous render drew, leaving the
// cursor at the start of the first of them.
func clearRenderedRows(w io.Writer, rows int) {
	if rows <= 0 {
		return
	}
	fmt.Fprint(w, "\r\033[2K")
	for i := 1; i < rows; i++ {
		fmt.Fprint(w, "\033[1A\033[2K")
	}
}

func readSelectorKey(f *os.File) (string, error) {
	var b [1]byte
	if _, err := f.Read(b[:]); err != nil {
		return "", err
	}
	switch b[0] {
	case '\r', '\n':
		return "enter", nil
	case 'q', 'Q':
		return "quit", nil
	case 'k', 'K':
		return "up", nil
	case 'j', 'J':
		return "down", nil
	case '?':
		return "help", nil
	case '\f':
		return "redraw", nil
	case '\x1b':
		var rest [2]byte
		n, _ := readWithTimeout(f, rest[:], 100*time.Millisecond)
		if n == 2 && rest[0] == '[' {
			switch rest[1] {
			case 'A':
				return "up", nil
			case 'B':
				return "down", nil
			}
		}
		return "unknown", nil
	default:
		if b[0] >= '1' && b[0] <= '9' {
			return fmt.Sprintf("digit:%c", b[0]), nil
		}
		return "unknown", nil
	}
}

func stdinIsTerminal() bool {
	info, err := os.Stdin.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

func selectorOutput() (*os.File, func()) {
	f, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return os.Stdout, func() {}
	}
	return f, func() { _ = f.Close() }
}

func enableRawMode(fd int) (func(), error) {
	var old syscall.Termios
	if err := ioctlTermios(fd, syscall.TCGETS, &old); err != nil {
		return nil, err
	}
	next := old
	next.Lflag &^= syscall.ECHO | syscall.ICANON
	next.Cc[syscall.VMIN] = 1
	next.Cc[syscall.VTIME] = 0
	if err := ioctlTermios(fd, syscall.TCSETS, &next); err != nil {
		return nil, err
	}
	return func() {
		_ = ioctlTermios(fd, syscall.TCSETS, &old)
	}, nil
}

func ioctlTermios(fd int, req uintptr, termios *syscall.Termios) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, uintptr(unsafe.Pointer(termios)))
	if errno != 0 {
		return errno
	}
	return nil
}

func readWithTimeout(f *os.File, b []byte, timeout time.Duration) (int, error) {
	fd := int(f.Fd())
	var set syscall.FdSet
	set.Bits[fd/64] |= 1 << (uint(fd) % 64)
	tv := syscall.NsecToTimeval(timeout.Nanoseconds())
	ready, err := syscall.Select(fd+1, &set, nil, nil, &tv)
	if err != nil || ready <= 0 {
		return 0, err
	}
	return f.Read(b)
}
