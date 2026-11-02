package firebase

import "testing"

func TestRestrictionObservationRetainsGPSClockAndReentryRules(t *testing.T) {
	state := map[string]any{}
	observe := func(inside bool, fix, now int64, expected string) {
		t.Helper()
		transition, updates := nextRestrictionObservation(state, inside, fix, now)
		if transition != expected {
			t.Fatalf("fix=%d: got %s, want %s", fix, transition, expected)
		}
		for key, value := range updates {
			state[key] = value
		}
	}
	observe(true, 1000, 1000, "candidate_entry")
	observe(true, 1000, 1100, "ignored") // Publishing one GPS fix twice is not evidence.
	observe(true, 900, 1200, "ignored")
	observe(true, 2000, 2000, "enter")
	observe(false, 3000, 3000, "candidate_exit")
	observe(false, 4000, 4000, "exit")
	observe(true, 5000, 5000, "candidate_entry")
	observe(true, 6000, 6000, "reentry_cooldown")
	observe(true, 65000, 65000, "enter")
}
