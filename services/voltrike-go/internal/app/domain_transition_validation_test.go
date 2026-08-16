package app

import "testing"

func TestSupportedBookingTransitionActions(t *testing.T) {
	t.Parallel()

	for _, action := range []string{
		"accept",
		"arrived",
		"start",
		"advanceStop",
		"payment",
		"complete",
		"cancel",
		"noShow",
		"decline",
		"dispute",
		"receipt",
	} {
		action := action
		t.Run(action, func(t *testing.T) {
			t.Parallel()
			if !supportedBookingTransitionAction(action) {
				t.Fatalf("expected %q to be supported", action)
			}
		})
	}
}

func TestUnsupportedBookingTransitionAction(t *testing.T) {
	t.Parallel()

	if supportedBookingTransitionAction("skipAllStops") {
		t.Fatal("unexpectedly accepted an unknown booking transition")
	}
}
