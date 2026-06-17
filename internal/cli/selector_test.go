package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestRenderSelectorIncludesOptionsAndHelp(t *testing.T) {
	var out bytes.Buffer
	renderSelector(&out, "choose", []Option{
		{Label: "run", Summary: "Start a practice scenario"},
		{Label: "status", Summary: "Show state"},
	}, 1, true)

	got := out.String()
	for _, want := range []string{
		"\033[H\033[2J",
		"choose",
		"  1. run",
		"> 2. status",
		"Up/k, Down/j",
		"Enter",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("rendered selector missing %q:\n%s", want, got)
		}
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
