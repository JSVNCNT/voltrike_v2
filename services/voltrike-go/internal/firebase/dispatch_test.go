package firebase

import (
	"testing"
	"time"
)

func TestDispatchRankingMetricsUsesCurrentManilaDayAndSmoothedScores(t *testing.T) {
	driver := map[string]any{
		"rating": 5.0, "ratingCount": 10,
		"dispatchStats": map[string]any{
			"dailyAwardDate": "2026-08-09", "dailyAwardCount": 3,
			"completedAssignments": 11, "driverFaultCancellations": 1,
		},
	}
	daily, reliability, quality := dispatchRankingMetrics(driver, time.Date(2026, 8, 8, 16, 30, 0, 0, time.UTC))
	if daily != 3 || reliability != 0.909091 || quality != 4.75 {
		t.Fatalf("unexpected ranking metrics: daily=%d reliability=%f quality=%f", daily, reliability, quality)
	}
}

func TestDispatchRankingMetricsResetsStaleDailyAwards(t *testing.T) {
	driver := map[string]any{"dispatchStats": map[string]any{
		"dailyAwardDate": "2026-08-08", "dailyAwardCount": 9,
	}}
	daily, reliability, quality := dispatchRankingMetrics(driver, time.Date(2026, 8, 9, 1, 0, 0, 0, time.UTC))
	if daily != 0 || reliability != 0.9 || quality != 4.5 {
		t.Fatalf("unexpected fallback metrics: daily=%d reliability=%f quality=%f", daily, reliability, quality)
	}
}

func TestNextDriverDispatchStatsTracksAwardsAndOutcomes(t *testing.T) {
	now := time.Date(2026, 8, 9, 2, 0, 0, 0, time.UTC)
	assigned := nextDriverDispatchStats(map[string]any{}, "assigned", now)
	if integer(assigned, "dailyAwardCount") != 1 || integer(assigned, "assignmentCount") != 1 {
		t.Fatalf("assignment was not counted: %#v", assigned)
	}
	driver := map[string]any{"dispatchStats": assigned}
	completed := nextDriverDispatchStats(driver, "completed", now)
	if integer(completed, "completedAssignments") != 1 || integer(completed, "dailyAwardCount") != 1 {
		t.Fatalf("completion was not counted: %#v", completed)
	}
	driver["dispatchStats"] = completed
	fault := nextDriverDispatchStats(driver, "driver_fault_cancelled", now)
	if integer(fault, "cancellationCount") != 1 || integer(fault, "driverFaultCancellations") != 1 {
		t.Fatalf("driver fault was not counted: %#v", fault)
	}
}
