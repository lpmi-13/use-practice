package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestRenderSelectorIncludesOptionsAndHelp(t *testing.T) {
	var out bytes.Buffer
	rows := renderSelector(&out, palette{}, 80, "choose", []Option{
		{Label: "run", Summary: "Start a practice scenario"},
		{Label: "status", Summary: "Show state"},
	}, 1, true)

	got := out.String()
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
	if strings.Contains(got, "\033[2J") {
		t.Fatalf("selector should redraw in place, not clear the screen:\n%q", got)
	}
	if strings.HasSuffix(got, "\n") {
		t.Fatalf("selector should leave the cursor on its last line:\n%q", got)
	}
	// Title, two options, "Keys:" and five key lines.
	if rows != 9 {
		t.Fatalf("rows = %d, want 9", rows)
	}
}

func TestRenderSelectorStylesWithColour(t *testing.T) {
	var out bytes.Buffer
	renderSelector(&out, palette{color: true}, 80, "choose", []Option{
		{Label: "cpu", Summary: "CPU pressure"},
		{Label: "disk", Summary: "Disk pressure"},
	}, 0, false)

	got := out.String()
	for _, want := range []string{
		"\033[1mchoose\033[0m",
		"> \033[7m1. cpu",
		"  2. disk         Disk pressure",
		"Enter \033[2mchoose\033[0m",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("styled selector missing %q:\n%q", want, got)
		}
	}
	// Summaries are how learners choose a profile, so they stay normal weight.
	if strings.Contains(got, "\033[2mCPU pressure") {
		t.Fatalf("summary should not be faint:\n%q", got)
	}
}

func TestRenderSelectorCountsWrappedRows(t *testing.T) {
	var out bytes.Buffer
	rows := renderSelector(&out, palette{color: true}, 20, "choose", []Option{
		{Label: "cpu", Summary: "a summary long enough to wrap"},
	}, 0, false)

	// "> 1. cpu          a summary long enough to wrap" is 47 columns: 3 rows.
	// The short help line is 49 columns once escapes are skipped: 3 rows.
	if rows != 1+3+3 {
		t.Fatalf("rows = %d, want 7", rows)
	}
}

func TestClearRenderedRowsErasesUpwards(t *testing.T) {
	var out bytes.Buffer
	clearRenderedRows(&out, 3)
	want := "\r\033[2K\033[1A\033[2K\033[1A\033[2K"
	if out.String() != want {
		t.Fatalf("got %q, want %q", out.String(), want)
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
