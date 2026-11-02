package firebase

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/voltrike/voltrike-go/internal/config"
	"google.golang.org/api/iterator"
)

const (
	demoActivationProject = "voltrike-v2"
	demoActivationTag     = "bacolod-admin-demo-2026"
	demoActivationToda    = "barangay-40-toda-ms0q43rw"
	demoActivationEnd     = "2027-02-28"
)

var demoActivationZone = time.FixedZone("UTC+8", 8*60*60)

type demoActivationRecord struct {
	ID         string         `json:"id"`
	Data       map[string]any `json:"data"`
	UpdateTime time.Time      `json:"updateTime"`
}

type demoActivationWrite struct {
	collection string
	id         string
	create     map[string]any
	updates    []firestore.Update
	updateTime time.Time
}

// OpenDemoActivation opens only Firestore for the narrowly scoped scheduled
// synthetic-data job. It deliberately does not load API, Routes, or mail keys.
func OpenDemoActivation(ctx context.Context, projectID string) (*Store, func(), error) {
	if projectID != demoActivationProject {
		return nil, nil, fmt.Errorf("demo activation is restricted to its original Firebase project")
	}
	client, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		return nil, nil, fmt.Errorf("open demo activation Firestore: %w", err)
	}
	return &Store{firestore: client, cfg: config.Config{ProjectID: projectID}}, func() { _ = client.Close() }, nil
}

// ActivateDemo preserves the retired hourly Node job's fixed dataset, UTC+8
// calendar, timestamp gate, profile summaries, and final integrity checks.
func (store *Store) ActivateDemo(ctx context.Context) (map[string]any, error) {
	return store.activateDemoAt(ctx, time.Now().UTC())
}

func (store *Store) activateDemoAt(ctx context.Context, now time.Time) (map[string]any, error) {
	if store.cfg.ProjectID != demoActivationProject {
		return nil, fmt.Errorf("demo activation is restricted to its original Firebase project")
	}
	today := now.In(demoActivationZone).Format(time.DateOnly)
	if today > demoActivationEnd {
		return map[string]any{"activated": false, "activatedThrough": today, "reason": "demo_period_ended"}, nil
	}
	if store.firestore == nil {
		return nil, fmt.Errorf("demo activation Firestore is unavailable")
	}
	held, err := store.readDemoActivationRecords(ctx, "demoSeedFutureRecords")
	if err != nil {
		return nil, err
	}
	eligible, err := eligibleDemoActivationRecords(held, now)
	if err != nil {
		return nil, err
	}
	if len(eligible) == 0 {
		return map[string]any{"activated": false, "activatedThrough": today, "addedLiveDocuments": 0, "reason": "no_records_due"}, nil
	}
	before := map[string][]demoActivationRecord{"demoSeedFutureRecords": held}
	for _, collection := range []string{"bookings", "settlements", "ratings", "reports", "drivers", "passengers"} {
		before[collection], err = store.readDemoActivationRecords(ctx, collection)
		if err != nil {
			return nil, err
		}
	}
	writes, added, err := planDemoActivationWrites(eligible, before, now)
	if err != nil {
		return nil, err
	}
	// Validate every profile write target before any held record is activated.
	if _, err := planDemoProfileSummaries(before, nil, now); err != nil {
		return nil, err
	}
	backupFile, err := backupDemoActivation(before, now)
	if err != nil {
		return nil, err
	}
	if err := store.commitDemoActivation(ctx, writes); err != nil {
		return nil, err
	}
	after := map[string][]demoActivationRecord{}
	for _, collection := range []string{"bookings", "settlements", "ratings", "reports"} {
		after[collection], err = store.readDemoActivationRecords(ctx, collection)
		if err != nil {
			return nil, err
		}
	}
	profiles, err := planDemoProfileSummaries(before, after, now)
	if err != nil {
		return nil, err
	}
	if err := store.commitDemoActivation(ctx, profiles); err != nil {
		return nil, err
	}
	after["demoSeedFutureRecords"], err = store.readDemoActivationRecords(ctx, "demoSeedFutureRecords")
	if err != nil {
		return nil, err
	}
	daily, err := verifyDemoActivation(before, after, now)
	if err != nil {
		return nil, err
	}
	summary := map[string]any{
		"activatedThrough": today, "addedLiveDocuments": added,
		"liveBookings": len(after["bookings"]), "liveSettlements": len(after["settlements"]),
		"dailyBookings": daily, "backupFile": backupFile,
	}
	encoded, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(filepath.Dir(backupFile), "activation-summary.json"), encoded, 0600); err != nil {
		return nil, fmt.Errorf("write demo activation summary: %w", err)
	}
	return summary, nil
}

func (store *Store) readDemoActivationRecords(ctx context.Context, collection string) ([]demoActivationRecord, error) {
	documents := store.firestore.Collection(collection).Where("seedTag", "==", demoActivationTag).Documents(ctx)
	defer documents.Stop()
	result := []demoActivationRecord{}
	for {
		document, err := documents.Next()
		if err == iterator.Done {
			return result, nil
		}
		if err != nil {
			return nil, fmt.Errorf("read synthetic %s records: %w", collection, err)
		}
		result = append(result, demoActivationRecord{ID: document.Ref.ID, Data: document.Data(), UpdateTime: document.UpdateTime})
	}
}

func eligibleDemoActivationRecords(held []demoActivationRecord, now time.Time) ([]demoActivationRecord, error) {
	today := now.In(demoActivationZone).Format(time.DateOnly)
	if today > demoActivationEnd {
		return nil, nil
	}
	due := []demoActivationRecord{}
	pending := map[string]bool{}
	for _, record := range held {
		date := text(record.Data, "date")
		if _, err := time.Parse(time.DateOnly, date); err != nil {
			return nil, fmt.Errorf("invalid synthetic holding date")
		}
		if date > today || date > demoActivationEnd || text(record.Data, "activationStatus") != "held" {
			continue
		}
		data, ok := record.Data["data"].(map[string]any)
		if !ok || text(data, "bookingId") == "" {
			return nil, fmt.Errorf("synthetic holding has no booking data")
		}
		if demoHasFutureTimestamp(data, now) {
			pending[text(data, "bookingId")] = true
		}
		due = append(due, record)
	}
	eligible := []demoActivationRecord{}
	for _, record := range due {
		data := record.Data["data"].(map[string]any)
		if !pending[text(data, "bookingId")] {
			eligible = append(eligible, record)
		}
	}
	return eligible, nil
}

func demoHasFutureTimestamp(data map[string]any, now time.Time) bool {
	for _, field := range []string{"createdAt", "updatedAt", "completedAt", "settlementTimestamp"} {
		if value, ok := data[field].(time.Time); ok && value.After(now) {
			return true
		}
	}
	return false
}

func demoSyntheticScope(data map[string]any) bool {
	return data["isDemo"] == true && text(data, "seedTag") == demoActivationTag && text(data, "todaId") == demoActivationToda
}

func demoLiveCollection(collection string) bool {
	return collection == "bookings" || collection == "settlements" || collection == "ratings" || collection == "reports"
}

func planDemoActivationWrites(eligible []demoActivationRecord, before map[string][]demoActivationRecord, now time.Time) ([]demoActivationWrite, int, error) {
	live := map[string]map[string]demoActivationRecord{}
	for _, collection := range []string{"bookings", "settlements", "ratings", "reports"} {
		live[collection] = map[string]demoActivationRecord{}
		for _, record := range before[collection] {
			live[collection][record.ID] = record
		}
	}
	writes := []demoActivationWrite{}
	added := 0
	for _, held := range eligible {
		if !demoSyntheticScope(held.Data) {
			return nil, 0, fmt.Errorf("invalid held synthetic scope")
		}
		collection, id := text(held.Data, "originalCollection"), text(held.Data, "originalId")
		if !demoLiveCollection(collection) || id == "" || strings.Contains(id, "/") || held.ID == "" || strings.Contains(held.ID, "/") || held.UpdateTime.IsZero() {
			return nil, 0, fmt.Errorf("invalid held synthetic destination")
		}
		data, ok := held.Data["data"].(map[string]any)
		if !ok || !demoSyntheticScope(data) || text(data, "bookingId") == "" || demoHasFutureTimestamp(data, now) {
			return nil, 0, fmt.Errorf("invalid held synthetic payload")
		}
		if existing, exists := live[collection][id]; exists {
			if !demoSyntheticScope(existing.Data) {
				return nil, 0, fmt.Errorf("synthetic destination has invalid existing scope")
			}
		} else {
			writes = append(writes, demoActivationWrite{collection: collection, id: id, create: data})
			// Duplicate holding destinations must not schedule duplicate creates.
			live[collection][id] = demoActivationRecord{ID: id, Data: data}
			added++
		}
		writes = append(writes, demoActivationWrite{collection: "demoSeedFutureRecords", id: held.ID, updateTime: held.UpdateTime, updates: []firestore.Update{{Path: "activationStatus", Value: "activated"}, {Path: "activatedAt", Value: now}}})
	}
	return writes, added, nil
}

func planDemoProfileSummaries(before, after map[string][]demoActivationRecord, now time.Time) ([]demoActivationWrite, error) {
	writes := []demoActivationWrite{}
	for _, driver := range before["drivers"] {
		uid := text(driver.Data, "uid")
		if !demoSyntheticScope(driver.Data) || uid == "" || driver.UpdateTime.IsZero() {
			return nil, fmt.Errorf("invalid synthetic driver scope")
		}
		trips, count, gross, rating := 0, 0, 0.0, 0.0
		for _, settlement := range after["settlements"] {
			if text(settlement.Data, "driverId") == uid {
				trips++
				gross += number(settlement.Data, "grossFare")
			}
		}
		for _, feedback := range after["ratings"] {
			if text(feedback.Data, "driverId") == uid {
				count++
				rating += number(feedback.Data, "rating")
			}
		}
		if count > 0 {
			rating /= float64(count)
		}
		writes = append(writes, demoActivationWrite{collection: "drivers", id: driver.ID, updateTime: driver.UpdateTime, updates: []firestore.Update{{Path: "completedTrips", Value: trips}, {Path: "totalEarnings", Value: gross}, {Path: "ratingCount", Value: count}, {Path: "rating", Value: rating}, {Path: "updatedAt", Value: now}}})
	}
	for _, passenger := range before["passengers"] {
		uid := text(passenger.Data, "uid")
		// The original synthetic passenger profiles intentionally have no TODA.
		// A present TODA must still match; ordinary/unmarked users are excluded.
		passengerToda := text(passenger.Data, "todaId")
		if passenger.Data["isDemo"] != true || text(passenger.Data, "seedTag") != demoActivationTag || (passengerToda != "" && passengerToda != demoActivationToda) || uid == "" || passenger.UpdateTime.IsZero() {
			return nil, fmt.Errorf("invalid synthetic passenger scope")
		}
		trips := 0
		for _, booking := range after["bookings"] {
			if text(booking.Data, "passengerId") == uid && text(booking.Data, "status") == "completed" {
				trips++
			}
		}
		writes = append(writes, demoActivationWrite{collection: "passengers", id: passenger.ID, updateTime: passenger.UpdateTime, updates: []firestore.Update{{Path: "totalTrips", Value: trips}, {Path: "updatedAt", Value: now}}})
	}
	return writes, nil
}

func (store *Store) commitDemoActivation(ctx context.Context, writes []demoActivationWrite) error {
	for start := 0; start < len(writes); start += 200 {
		end := min(start+200, len(writes))
		batch := store.firestore.Batch()
		for _, write := range writes[start:end] {
			ref := store.firestore.Collection(write.collection).Doc(write.id)
			if write.create != nil {
				batch.Create(ref, write.create)
			} else {
				batch.Update(ref, write.updates, firestore.LastUpdateTime(write.updateTime))
			}
		}
		if _, err := batch.Commit(ctx); err != nil {
			return fmt.Errorf("commit synthetic activation batch: %w", err)
		}
	}
	return nil
}

func verifyDemoActivation(before, after map[string][]demoActivationRecord, now time.Time) (map[string]int, error) {
	today := now.In(demoActivationZone).Format(time.DateOnly)
	daily, expected, ids := map[string]int{}, map[string]int{}, map[string]bool{}
	for _, booking := range after["bookings"] {
		created, ok := booking.Data["createdAt"].(time.Time)
		if !ok || created.After(now) || created.In(demoActivationZone).Format(time.DateOnly) > today {
			return nil, fmt.Errorf("future or invalid live synthetic booking timestamp")
		}
		daily[created.In(demoActivationZone).Format(time.DateOnly)]++
		ids[text(booking.Data, "bookingId")] = true
	}
	for _, held := range before["demoSeedFutureRecords"] {
		date := text(held.Data, "date")
		if text(held.Data, "originalCollection") == "bookings" && date < today {
			expected[date]++
		}
	}
	for date, count := range expected {
		if daily[date] != count {
			return nil, fmt.Errorf("synthetic daily booking count mismatch for %s", date)
		}
	}
	for _, collection := range []string{"settlements", "ratings", "reports"} {
		for _, record := range after[collection] {
			if !ids[text(record.Data, "bookingId")] {
				return nil, fmt.Errorf("orphaned synthetic %s record", collection)
			}
		}
	}
	heldAfter := map[string]time.Time{}
	for _, record := range after["demoSeedFutureRecords"] {
		heldAfter[record.ID] = record.UpdateTime
	}
	for _, record := range before["demoSeedFutureRecords"] {
		if text(record.Data, "date") > today && !heldAfter[record.ID].Equal(record.UpdateTime) {
			return nil, fmt.Errorf("future synthetic holding was changed")
		}
	}
	return daily, nil
}

func backupDemoActivation(before map[string][]demoActivationRecord, now time.Time) (string, error) {
	directory := filepath.Join(os.TempDir(), "voltrike-demo-activation")
	if err := os.MkdirAll(directory, 0700); err != nil {
		return "", fmt.Errorf("create demo activation backup directory: %w", err)
	}
	encoded, err := json.MarshalIndent(before, "", "  ")
	if err != nil {
		return "", fmt.Errorf("encode demo activation backup: %w", err)
	}
	path := filepath.Join(directory, fmt.Sprintf("before-activation-%d.json", now.UnixMilli()))
	if err := os.WriteFile(path, encoded, 0600); err != nil {
		return "", fmt.Errorf("write demo activation backup: %w", err)
	}
	return path, nil
}
