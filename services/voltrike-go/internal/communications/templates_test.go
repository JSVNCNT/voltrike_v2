package communications

import (
	"strings"
	"testing"
)

func TestAuthTemplatesPreserveFirebaseLinksAndEscapeProfileText(t *testing.T) {
	link := "https://example.test/action?mode=verifyEmail&oobCode=abc"
	for _, message := range []Message{VerificationEmail(`<script>alert("x")</script>`, link, "https://example.test/logo.png"), PasswordResetEmail(`<script>alert("x")</script>`, link, "")} {
		if strings.Contains(message.HTML, "<script>") || !strings.Contains(message.HTML, "&lt;script&gt;") {
			t.Fatal("profile text was not HTML escaped")
		}
		if !strings.Contains(message.Text, link) || !strings.Contains(message.HTML, "mode=verifyEmail&amp;oobCode=abc") {
			t.Fatal("Firebase action link did not survive both message formats")
		}
	}
	message := PasswordResetEmail("Passenger", link, "")
	if message.Subject != "Reset your VolTrike password" || !strings.Contains(message.Text, "For your security, VolTrike will never ask you to reply with your password or verification code.") {
		t.Fatal("password recovery branding or security copy changed")
	}
}

func TestSafetyTemplateContainsOperationalContextWithoutAdditionalSecrets(t *testing.T) {
	message := SafetyAlertEmail(SafetyAlert{RecipientName: "TODA Admin", EventLabel: "Unacknowledged VolTrike SOS", AdminPortalURL: "https://admin.example.test", Incident: map[string]any{
		"bookingId": "ride-1", "reporterRole": "passenger", "escalationLevel": int64(2), "todaName": "Central", "pickupAddress": "Main & First", "destinationAddress": "Market", "passengerPhone": "PRIVATE_PHONE", "driverToken": "PRIVATE_TOKEN",
	}})
	if message.Subject != "Escalated VolTrike SOS - ride-1" {
		t.Fatal("escalation subject changed")
	}
	for _, expected := range []string{"Booking: ride-1", "Reported by: passenger", "TODA: Central", "Pickup: Main & First", "Destination: Market", "Open Safety Incidents:", "https://admin.example.test"} {
		if !strings.Contains(message.Text, expected) {
			t.Fatalf("missing operational context %q", expected)
		}
	}
	if strings.Contains(message.HTML+message.Text, "PRIVATE_") || !strings.Contains(message.HTML, "Main &amp; First") {
		t.Fatal("safety template leaked extra fields or failed to escape facts")
	}
}

func TestTodaTemplatesCoverEveryExistingLifecycleStatus(t *testing.T) {
	for status, title := range map[string]string{"submitted": "Application received", "approved": "Administrator access approved", "declined": "Application requires follow-up"} {
		message, err := TodaApplicationEmail(TodaApplication{AdministratorName: "Officer", TodaName: "Central", Status: status, AdminPortalURL: "https://admin.example.test"})
		if err != nil || message.Subject != "VolTrike TODA application - "+title || !strings.Contains(message.Text, "TODA: Central") || !strings.Contains(message.Text, "https://admin.example.test") {
			t.Fatalf("TODA %s message did not preserve its copy: %v", status, err)
		}
	}
	if _, err := TodaApplicationEmail(TodaApplication{Status: "invented"}); err == nil {
		t.Fatal("accepted unsupported TODA lifecycle status")
	}
}
