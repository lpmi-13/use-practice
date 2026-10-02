package cli

import "testing"

func TestDetectColor(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		tty     bool
		noColor bool
		want    bool
	}{
		{name: "terminal", tty: true, want: true},
		{name: "pipe", tty: false, want: false},
		{name: "NO_COLOR", env: map[string]string{"NO_COLOR": "1"}, tty: true, want: false},
		{name: "dumb terminal", env: map[string]string{"TERM": "dumb"}, tty: true, want: false},
		{name: "flag", tty: true, noColor: true, want: false},
		{name: "force on", env: map[string]string{"USE_PRACTICE_COLOR": "always"}, tty: false, want: true},
		{name: "force off", env: map[string]string{"USE_PRACTICE_COLOR": "never"}, tty: true, want: false},
		{name: "flag beats force on", env: map[string]string{"USE_PRACTICE_COLOR": "always"}, noColor: true, want: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			getenv := func(k string) string { return tt.env[k] }
			if got := detectColor(getenv, tt.tty, tt.noColor); got != tt.want {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
		})
	}
}

func TestPlainPaletteLeavesTextAlone(t *testing.T) {
	p := palette{}
	if got := p.bold("x") + p.faint("y") + p.reverse("z") + p.accent("c") + p.heading("h") + p.bad("a") + p.warn("b"); got != "xyzchab" {
		t.Fatalf("got %q", got)
	}
}

func TestVisibleWidthSkipsEscapes(t *testing.T) {
	p := palette{color: true}
	tests := []struct {
		in   string
		want int
	}{
		{"plain", 5},
		{p.bold("bold"), 4},
		{"> " + p.reverse("1. cpu"), 8},
		{"↑/k ↓/j", 7},
		{"\033[1A\033[2K", 0},
	}
	for _, tt := range tests {
		if got := visibleWidth(tt.in); got != tt.want {
			t.Errorf("visibleWidth(%q) = %d, want %d", tt.in, got, tt.want)
		}
	}
}

func TestPadRightUsesVisibleWidth(t *testing.T) {
	p := palette{color: true}
	got := padRight(p.warn("exited"), 10)
	if visibleWidth(got) != 10 {
		t.Fatalf("padded width = %d, want 10: %q", visibleWidth(got), got)
	}
}
