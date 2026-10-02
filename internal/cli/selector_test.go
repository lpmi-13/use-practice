package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestRenderSelectorIncludesOptionsAndHelp(t *testing.T) {
	var out bytes.Buffer
	renderSelector(&out, palette{}, "choose", []Option{
		{Label: "run", Summary: "Start a practice scenario"},
		{Label: "status", Summary: "Show state"},
	}, 1, true)

	got := out.String()
	if !strings.HasPrefix(got, "\033[H\033[2J") {
		t.Fatalf("selector should clear the screen before drawing: %q", got)
	}
	for _, want := range []string{
		"choose",
		"  1. run",
		"> 2. status",
		"↑/k, ↓/j",
		"Enter",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("rendered selector missing %q:\n%s", want, got)
		}
	}
	if strings.HasSuffix(got, "\n") {
		t.Fatalf("selector should leave the cursor on its last line: %q", got)
	}
}

func TestRenderSelectorStylesWithColour(t *testing.T) {
	var out bytes.Buffer
	renderSelector(&out, palette{color: true}, "choose", []Option{
		{Label: "cpu", Summary: "CPU pressure"},
		{Label: "disk", Summary: "Disk pressure"},
	}, 0, false)

	got := out.String()
	for _, want := range []string{
		"\033[1;36mchoose\033[0m",
		"\033[36m>\033[0m \033[7m1. cpu",
		"  2. disk         Disk pressure",
		"Enter \033[2mchoose\033[0m",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("styled selector missing %q:\n%q", want, got)
		}
	}
	if strings.Contains(got, "\033[2mCPU pressure") {
		t.Fatalf("profile summaries should stay at normal brightness: %q", got)
	}
}

func TestRenderSelectorClearsBetweenMenuSteps(t *testing.T) {
	var out bytes.Buffer
	renderSelector(&out, palette{}, "choose command", []Option{
		{Label: "run", Summary: "Start a scenario"},
	}, 0, false)
	renderSelector(&out, palette{}, "choose resource", []Option{
		{Label: "cpu", Summary: "CPU pressure"},
	}, 0, false)
	parts := strings.Split(out.String(), "\033[H\033[2J")
	if len(parts) != 3 || !strings.Contains(parts[1], "choose command") || !strings.Contains(parts[2], "choose resource") {
		t.Fatalf("each menu step should start on a cleared screen: %q", out.String())
	}
}

func TestReadSelectorKey(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "enter", in: "\n", want: "enter"},
		{name: "up", in: "k", want: "up"},
		{name: "down", in: "j", want: "down"},
		{name: "digit", in: "3", want: "digit:3"},
		{name: "help", in: "?", want: "help"},
		{name: "quit", in: "q", want: "quit"},
		{name: "arrow up", in: "\x1b[A", want: "up"},
		{name: "arrow down", in: "\x1b[B", want: "down"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, err := os.CreateTemp(t.TempDir(), "key")
			if err != nil {
				t.Fatal(err)
			}
			defer f.Close()
			if _, err := f.WriteString(tt.in); err != nil {
				t.Fatal(err)
			}
			if _, err := f.Seek(0, 0); err != nil {
				t.Fatal(err)
			}

			got, err := readSelectorKey(f)
			if err != nil {
				t.Fatal(err)
			}
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}
