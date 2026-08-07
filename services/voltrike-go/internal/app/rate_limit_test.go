package app

import (
	"testing"
	"time"
)

func TestPrincipalRateLimiterResetsAfterWindow(t *testing.T) {
	limiter := newPrincipalRateLimiter(2)
	now := time.Unix(100, 0)
	if !limiter.allow("user-1", now) || !limiter.allow("user-1", now) {
		t.Fatal("requests within limit were rejected")
	}
	if limiter.allow("user-1", now) {
		t.Fatal("request above limit was accepted")
	}
	if !limiter.allow("user-1", now.Add(time.Minute)) {
		t.Fatal("new window did not reset")
	}
}
