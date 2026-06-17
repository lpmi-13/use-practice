package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"syscall"
	"time"
	"unsafe"
)

var ErrSelectorQuit = errors.New("selector quit")

type SelectorSpec struct {
	Title    string
	Options  []Option
	Fallback string
}

type SelectorFunc func(SelectorSpec) (string, error)

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

	selected := 0
	showHelp := false
	renderSelector(out, spec.Title, spec.Options, selected, showHelp)

	for {
		key, err := readSelectorKey(os.Stdin)
		if err != nil {
			fmt.Fprintln(out)
			return "", err
		}
		switch key {
		case "up":
			selected = (selected + len(spec.Options) - 1) % len(spec.Options)
			renderSelector(out, spec.Title, spec.Options, selected, showHelp)
		case "down":
			selected = (selected + 1) % len(spec.Options)
			renderSelector(out, spec.Title, spec.Options, selected, showHelp)
		case "help":
			showHelp = !showHelp
			renderSelector(out, spec.Title, spec.Options, selected, showHelp)
		case "redraw":
			renderSelector(out, spec.Title, spec.Options, selected, showHelp)
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
					renderSelector(out, spec.Title, spec.Options, selected, showHelp)
				} else {
					fmt.Fprint(out, "\a")
				}
			} else {
				fmt.Fprint(out, "\a")
			}
		}
	}
}

func renderSelector(w io.Writer, title string, options []Option, selected int, showHelp bool) {
	fmt.Fprint(w, "\033[H\033[2J")
	fmt.Fprintln(w, title)
	for i, option := range options {
		cursor := " "
		if i == selected {
			cursor = ">"
		}
		fmt.Fprintf(w, "%s %d. %-12s %s\n", cursor, i+1, option.Label, option.Summary)
	}
	if showHelp {
		fmt.Fprintf(w, `Keys:
  Up/k, Down/j  move between options
  1-%d           jump to an option
  Enter         choose the highlighted option
  q             quit
  ?             hide help
`, len(options))
	} else {
		fmt.Fprintf(w, "Up/k Down/j move | 1-%d jump | Enter choose | q quit | ? help\n", len(options))
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

func selectorOutput() (io.Writer, func()) {
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
