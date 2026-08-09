package app

import (
	"context"
	"encoding/base64"
	"testing"
	"time"

	"github.com/voltrike/voltrike-go/internal/config"
	"github.com/voltrike/voltrike-go/internal/core"
)

type fakeStore struct {
	policy appPolicyResult
	cells  map[string]map[string]DispatchPresence
	loads  int
}

type appPolicyResult struct {
	value Policy
	err   error
}

func (store *fakeStore) LoadPolicy(context.Context) (Policy, error) {
	store.loads++
	return store.policy.value, store.policy.err
}

func (store *fakeStore) ReadDispatchCell(_ context.Context, cell string) (map[string]DispatchPresence, error) {
	return store.cells[cell], nil
}

type fakeRoutes struct{ routes []ProviderRoute }

func (routes fakeRoutes) Routes(context.Context, core.Coordinate, core.Coordinate) ([]ProviderRoute, error) {
	return routes.routes, nil
}

type fakeEligibilityStore struct{ *fakeStore }

func (store *fakeEligibilityStore) FilterEligibleDispatch(_ context.Context, candidates []DispatchCandidate, _ DispatchRequest) ([]DispatchCandidate, error) {
	for index := range candidates {
		candidates[index].TodaID = "toda-1"
	}
	return candidates, nil
}

func testConfig() config.Config {
	key, _ := base64.RawURLEncoding.DecodeString("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
	return config.Config{
		GoogleRoutesAPIKey:     "test",
		QuoteEncryptionKey:     key,
		PolicyCacheTTL:         60 * time.Second,
		RequestTimeout:         time.Second,
		DispatchCellDegrees:    0.05,
		DispatchRadiusMeters:   5000,
		MaximumDispatchResults: 40,
	}
}

func TestQuoteTokenIsBoundToActorAndInput(t *testing.T) {
	store := &fakeStore{policy: appPolicyResult{value: Policy{
		Fare: core.DefaultFare, Revision: "policy-1",
	}}}
	service, err := NewService(testConfig(), store)
	if err != nil {
		t.Fatal(err)
	}
	service.routes = fakeRoutes{routes: []ProviderRoute{{
		DistanceMeters: 1001,
		Duration:       "300s",
		Polyline:       "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
	}}}
	request := QuoteRequest{
		ActorID:     "passenger-1",
		Pickup:      core.Coordinate{Latitude: 38.5, Longitude: -120.2},
		Destination: core.Coordinate{Latitude: 43.252, Longitude: -126.453},
		IssueToken:  true,
	}
	response, err := service.Quote(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	if response.QuoteToken == "" || response.Quote.EstimatedFare != 25 {
		t.Fatalf("unexpected response: %#v", response)
	}
	consumed, err := service.ConsumeQuote(context.Background(), QuoteTokenRequest{
		ActorID:     request.ActorID,
		Pickup:      request.Pickup,
		Destination: request.Destination,
		QuoteToken:  response.QuoteToken,
	})
	if err != nil || consumed.PolicyRevision != "policy-1" {
		t.Fatalf("consume err=%v quote=%#v", err, consumed)
	}
	_, err = service.ConsumeQuote(context.Background(), QuoteTokenRequest{
		ActorID:     "passenger-2",
		Pickup:      request.Pickup,
		Destination: request.Destination,
		QuoteToken:  response.QuoteToken,
	})
	if err == nil {
		t.Fatal("token was accepted for another actor")
	}
	if store.loads != 1 {
		t.Fatalf("policy loads=%d, want one cached load", store.loads)
	}
}

func TestDispatchReadsNearbyCellSamples(t *testing.T) {
	pickup := core.Coordinate{Latitude: 10.67, Longitude: 122.95}
	cell := surroundingCells(pickup, 0.05)[4]
	store := &fakeStore{cells: map[string]map[string]DispatchPresence{
		cell: {
			"near": {
				DriverID: "near", Latitude: 10.671, Longitude: 122.951,
				Timestamp: time.Now().UnixMilli(), Accuracy: 5, Online: true,
			},
			"stale": {
				DriverID: "stale", Latitude: 10.671, Longitude: 122.951,
				Timestamp: time.Now().Add(-time.Minute).UnixMilli(), Accuracy: 5, Online: true,
			},
		},
	}}
	service, err := NewService(testConfig(), store)
	if err != nil {
		t.Fatal(err)
	}
	result, err := service.DispatchCandidates(context.Background(), DispatchRequest{Pickup: pickup})
	if err != nil {
		t.Fatal(err)
	}
	if len(result) != 1 || result[0].DriverID != "near" {
		t.Fatalf("unexpected candidates: %#v", result)
	}
}

func TestDispatchRepairsLegacyPresenceThroughAuthoritativeEligibility(t *testing.T) {
	pickup := core.Coordinate{Latitude: 10.67, Longitude: 122.95}
	cell := surroundingCells(pickup, 0.05)[4]
	store := &fakeEligibilityStore{fakeStore: &fakeStore{cells: map[string]map[string]DispatchPresence{
		cell: {
			"legacy": {
				DriverID: "legacy", Latitude: 10.671, Longitude: 122.951,
				Timestamp: time.Now().UnixMilli(), Accuracy: 5, Online: true,
				// Older projections have neither Available nor TodaID. Firestore
				// eligibility remains authoritative for both fields.
			},
		},
	}}}
	service, err := NewService(testConfig(), store)
	if err != nil {
		t.Fatal(err)
	}
	result, err := service.DispatchCandidates(context.Background(), DispatchRequest{
		Pickup: pickup, PrimaryTodaIDs: []string{"toda-1"}, RequiredSeats: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result) != 1 || result[0].DriverID != "legacy" || result[0].TodaID != "toda-1" {
		t.Fatalf("unexpected candidates: %#v", result)
	}
}

func TestSelectDispatchBatchPreservesBackupServiceTiers(t *testing.T) {
	candidates := []DispatchCandidate{
		{DriverID: "primary-1", ServicePriority: 0, DistanceMeters: 100},
		{DriverID: "primary-2", ServicePriority: 0, DistanceMeters: 200},
		{DriverID: "primary-3", ServicePriority: 0, DistanceMeters: 300},
		{DriverID: "primary-4", ServicePriority: 0, DistanceMeters: 400},
		{DriverID: "primary-5", ServicePriority: 0, DistanceMeters: 500},
		{DriverID: "secondary", ServicePriority: 1, DistanceMeters: 250},
		{DriverID: "fallback", ServicePriority: 2, DistanceMeters: 150},
	}
	selected := selectDispatchBatch(candidates, 5)
	ids := map[string]bool{}
	for _, candidate := range selected {
		ids[candidate.DriverID] = true
	}
	if len(selected) != 5 || !ids["secondary"] || !ids["fallback"] {
		t.Fatalf("backup tiers were not preserved: %#v", selected)
	}
}
