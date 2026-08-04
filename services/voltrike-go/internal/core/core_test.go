package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultFareAndCentavoRounding(t *testing.T) {
	if got := SnapshotFare(FareConfig{}); got != DefaultFare {
		t.Fatalf("zero fare config must use defaults: %#v", got)
	}
	config := DefaultFare
	config.BaseFare = 20.005
	config.DistanceStepPrice = 4.995
	config.AdditionalPassengerFee = 1.005
	config.BaggageFee = 2.005
	result := CalculateFare(config, 1001, 1, 1, false)
	if result.Total != 28.02 {
		t.Fatalf("centavo total = %.2f, want 28.02", result.Total)
	}
}

func TestSharedFareParityFixtures(t *testing.T) {
	path := filepath.Join("..", "..", "..", "..", "test", "fixtures", "fare_parity_v1.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Cases []struct {
			Name   string          `json:"name"`
			Config json.RawMessage `json:"config"`
			Input  struct {
				DistanceMeters       int  `json:"distanceMeters"`
				AdditionalPassengers int  `json:"additionalPassengers"`
				BaggageCount         int  `json:"baggageCount"`
				IsOutsideToda        bool `json:"isOutsideToda"`
			} `json:"input"`
			Expected struct {
				Total float64 `json:"total"`
			} `json:"expected"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	for _, item := range fixture.Cases {
		t.Run(item.Name, func(t *testing.T) {
			config := DefaultFare
			if string(item.Config) != "null" {
				if err := json.Unmarshal(item.Config, &config); err != nil {
					t.Fatal(err)
				}
			}
			result := CalculateFare(
				config,
				item.Input.DistanceMeters,
				item.Input.AdditionalPassengers,
				item.Input.BaggageCount,
				item.Input.IsOutsideToda,
			)
			if result.Total != item.Expected.Total {
				t.Fatalf("total = %.2f, want %.2f", result.Total, item.Expected.Total)
			}
		})
	}
}

func TestCoverageAndPolylineBoundaries(t *testing.T) {
	geofences := []Geofence{{
		ID: "zone", TodaID: "toda-1", IsActive: true, CoverageRevision: 2,
		Areas: []Area{{Points: []Coordinate{
			{Latitude: 10, Longitude: 122},
			{Latitude: 11, Longitude: 122},
			{Latitude: 11, Longitude: 123},
			{Latitude: 10, Longitude: 123},
		}}},
	}}
	coverage, err := ClassifyCoverage(
		geofences,
		Coordinate{Latitude: 10, Longitude: 122.5},
		Coordinate{Latitude: 10.5, Longitude: 122.5},
	)
	if err != nil {
		t.Fatal(err)
	}
	if coverage.CoverageClass != "intra_toda" || coverage.IsOutsideToda {
		t.Fatalf("unexpected coverage: %#v", coverage)
	}
	points, err := DecodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
	if err != nil || len(points) != 3 {
		t.Fatalf("decoded points=%d err=%v", len(points), err)
	}
	if _, err := DecodePolyline("_"); err == nil {
		t.Fatal("malformed polyline was accepted")
	}
}
