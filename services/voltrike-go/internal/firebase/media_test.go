package firebase

import (
	"testing"
	"time"
)

func TestFinalizedAccountMediaURL(t *testing.T) {
	store := &Store{bucketName: "voltrike.appspot.com"}
	valid := "https://firebasestorage.googleapis.com/v0/b/voltrike.appspot.com/o/final%2Fdrivers%2Fuser-1%2Flicense%2Ffile.jpg?alt=media&token=secret"
	if !store.isFinalizedAccountMediaURL(valid, "user-1", "drivers") {
		t.Fatal("expected finalized account media URL to be accepted")
	}
	invalid := []string{
		"https://evil.example/v0/b/voltrike.appspot.com/o/final%2Fdrivers%2Fuser-1%2Ffile.jpg?alt=media&token=secret",
		"https://firebasestorage.googleapis.com/v0/b/other.appspot.com/o/final%2Fdrivers%2Fuser-1%2Ffile.jpg?alt=media&token=secret",
		"https://firebasestorage.googleapis.com/v0/b/voltrike.appspot.com/o/final%2Fdrivers%2Fuser-2%2Ffile.jpg?alt=media&token=secret",
		"https://firebasestorage.googleapis.com/v0/b/voltrike.appspot.com/o/final%2Fdrivers%2Fuser-1%2Ffile.jpg?alt=media",
	}
	for _, candidate := range invalid {
		if store.isFinalizedAccountMediaURL(candidate, "user-1", "drivers") {
			t.Fatalf("expected URL to be rejected: %s", candidate)
		}
	}
}

func TestRegistrationUserIgnoresAuthorityFields(t *testing.T) {
	result := registrationUser(map[string]any{
		"email": "rider@example.com", "firstName": "Rider", "lastName": "One", "phoneNumber": "123",
		"role": "developer_admin", "isActive": false, "emailVerified": true, "completedTrips": 999,
	}, "uid-1", "passenger", "", "", time.Unix(1, 0).UTC())
	if result["role"] != "passenger" || result["isActive"] != true || result["emailVerified"] != false {
		t.Fatalf("authority fields were not server controlled: %#v", result)
	}
	if _, exists := result["completedTrips"]; exists {
		t.Fatal("unexpected client authority field survived registration sanitization")
	}
}
