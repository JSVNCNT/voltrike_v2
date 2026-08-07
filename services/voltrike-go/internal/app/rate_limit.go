package app

import (
	"sync"
	"time"
)

type principalRateWindow struct {
	started time.Time
	count   int
}

// principalRateLimiter is a bounded per-instance defense-in-depth limit. Auth,
// App Check, Cloud Run concurrency, and backend validation remain authoritative.
type principalRateLimiter struct {
	mu       sync.Mutex
	limit    int
	windows  map[string]principalRateWindow
	lastTrim time.Time
}

func newPrincipalRateLimiter(limit int) *principalRateLimiter {
	if limit <= 0 {
		return nil
	}
	return &principalRateLimiter{limit: limit, windows: map[string]principalRateWindow{}}
}

func (limiter *principalRateLimiter) allow(uid string, now time.Time) bool {
	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	if limiter.lastTrim.IsZero() || now.Sub(limiter.lastTrim) >= time.Minute {
		for key, window := range limiter.windows {
			if now.Sub(window.started) >= 2*time.Minute {
				delete(limiter.windows, key)
			}
		}
		limiter.lastTrim = now
	}
	window := limiter.windows[uid]
	if window.started.IsZero() || now.Sub(window.started) >= time.Minute {
		limiter.windows[uid] = principalRateWindow{started: now, count: 1}
		return true
	}
	if window.count >= limiter.limit {
		return false
	}
	window.count++
	limiter.windows[uid] = window
	return true
}
