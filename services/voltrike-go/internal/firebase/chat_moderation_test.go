package firebase

import "testing"

import "time"

func TestMaskModeratedPhrasePreservesContext(t *testing.T) {
	got, matched := maskModeratedPhrase("What the FUCK is this?", "fuck")
	if !matched || got != "What the F*** is this?" {
		t.Fatalf("got %q matched=%v", got, matched)
	}
}

func TestMaskModeratedPhraseUsesWordBoundaries(t *testing.T) {
	got, matched := maskModeratedPhrase("Scunthorpe and class", "ass")
	if matched || got != "Scunthorpe and class" {
		t.Fatalf("unexpected partial match %q", got)
	}
}

func TestMaskModeratedPhraseSupportsPhrases(t *testing.T) {
	got, matched := maskModeratedPhrase("you are stupid, really", "are stupid")
	if !matched || got != "you a** s*****, really" {
		t.Fatalf("got %q matched=%v", got, matched)
	}
}

func TestMaskModeratedPhraseMatchesStretchedSpelling(t *testing.T) {
	got, matched := maskModeratedPhraseAdvanced("That is fuuuuuck", "fuck", "word", true)
	if !matched || got != "That is f*******" {
		t.Fatalf("expected stretched spelling to be masked, got %q matched=%v", got, matched)
	}
}

func TestMaskModeratedPhraseSubstringMatchesCompound(t *testing.T) {
	got, matched := maskModeratedPhraseAdvanced("yudiputa", "puta", "substring", false)
	if !matched || got != "yudip***" {
		t.Fatalf("expected compound substring to be masked, got %q matched=%v", got, matched)
	}
}

func TestNormalizedModerationAliasesDeduplicates(t *testing.T) {
	got := normalizedModerationAliases([]string{"fck", "FCK", "fuck"}, "fuck")
	if len(got) != 1 || got[0] != "fck" {
		t.Fatalf("unexpected aliases: %#v", got)
	}
}

func TestChatModerationAudienceScopesDriverToToda(t *testing.T) {
	data := chatModerationIncidentData(chatModerationIncidentInput{
		Booking:   map[string]any{"driverId": "driver-1", "passengerId": "passenger-1", "todaId": "toda-1"},
		BookingID: "booking-1", MessageID: "message-1", SenderID: "driver-1",
	}, "incident-1", time.Now())
	if !contains(stringSlice(data["reviewAudience"]), "toda_admin") {
		t.Fatal("driver evidence must be visible to the driver's TODA")
	}
}

func TestChatModerationAudienceKeepsPassengerGlobal(t *testing.T) {
	data := chatModerationIncidentData(chatModerationIncidentInput{
		Booking:   map[string]any{"driverId": "driver-1", "passengerId": "passenger-1", "todaId": "toda-1"},
		BookingID: "booking-1", MessageID: "message-1", SenderID: "passenger-1",
	}, "incident-1", time.Now())
	if contains(stringSlice(data["reviewAudience"]), "toda_admin") {
		t.Fatal("passenger evidence must remain System Admin-only")
	}
}
