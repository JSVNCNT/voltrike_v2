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

func TestRideTypeFareAndCapacity(t *testing.T) {
	result := CalculateFareForRideType(DefaultFare, 1000, 0, 0, 1, false, "electric_tuktuk")
	if result.RideTypeFare != 10 || result.Total != 30 || result.RequestedVehicleType != "electric_tuktuk" {
		t.Fatalf("unexpected E-Tuktuk fare: %#v", result)
	}
	if RideTypeCanCarry("e_trike", 3) || !RideTypeCanCarry("electric_tuktuk", 4) {
		t.Fatal("ride capacity policy is incorrect")
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

func TestTwoDropoffsAggregateFareCoverageAndPolyline(t *testing.T) {
	config := DefaultFare
	config.AdditionalDropoffFee = 12.50
	result := CalculateFareForDropoffs(config, 1000, 0, 0, 2, false)
	if result.AdditionalDropoffs != 1 || result.AdditionalDropoffFare != 12.50 || result.Total != 32.50 {
		t.Fatalf("unexpected two-dropoff fare: %#v", result)
	}
	points := []Coordinate{{Latitude: 10.1, Longitude: 122.1}, {Latitude: 10.2, Longitude: 122.2}, {Latitude: 10.3, Longitude: 122.3}}
	encoded, err := EncodePolyline(points)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := DecodePolyline(encoded)
	if err != nil || len(decoded) != len(points) {
		t.Fatalf("combined polyline did not round-trip: points=%d err=%v", len(decoded), err)
	}
}

func TestOutsideTodaSurchargeRequiresConfiguredCoverage(t *testing.T) {
	pickup := Coordinate{Latitude: 10.5, Longitude: 122.5}
	destinationOutside := Coordinate{Latitude: 11.5, Longitude: 122.5}

	// Until a TODA coverage request has been approved into an active geofence,
	// legacy city-wide service remains available without a boundary surcharge.
	unconfigured, err := ClassifyCoverage(nil, pickup, destinationOutside)
	if err != nil {
		t.Fatal(err)
	}
	if unconfigured.Configured || unconfigured.IsOutsideToda || unconfigured.CoverageClass != "unconfigured_fallback" {
		t.Fatalf("unexpected unconfigured coverage: %#v", unconfigured)
	}

	approvedZone := []Geofence{{
		ID: "toda-1", TodaID: "toda-1", IsActive: true, CoverageRevision: 1,
		Areas: []Area{{Points: []Coordinate{
			{Latitude: 10, Longitude: 122},
			{Latitude: 11, Longitude: 122},
			{Latitude: 11, Longitude: 123},
			{Latitude: 10, Longitude: 123},
		}}},
	}}
	configured, err := ClassifyCoverage(approvedZone, pickup, destinationOutside)
	if err != nil {
		t.Fatal(err)
	}
	if !configured.Configured || !configured.IsOutsideToda || configured.CoverageClass != "destination_outside_coverage" {
		t.Fatalf("unexpected configured coverage: %#v", configured)
	}

	fare := DefaultFare
	fare.OutsideTodaSurcharge = 37.50
	insideFare := CalculateFare(fare, 1000, 0, 0, false)
	outsideFare := CalculateFare(fare, 1000, 0, 0, configured.IsOutsideToda)
	if outsideFare.BoundarySurcharge != 37.50 || outsideFare.Total != insideFare.Total+37.50 {
		t.Fatalf("outside surcharge was not applied once: inside=%#v outside=%#v", insideFare, outsideFare)
	}
}

func TestRestrictedDrivingAreaBlocksEndpointsAndRoutes(t *testing.T) {
	restriction := Restriction{
		ID: "local-road-ban", Type: "restricted_driving_area", IsActive: true,
		GeometryType: "polygon", Areas: []Area{{Points: []Coordinate{
			{Latitude: 10, Longitude: 122},
			{Latitude: 11, Longitude: 122},
			{Latitude: 11, Longitude: 123},
			{Latitude: 10, Longitude: 123},
		}}},
	}
	inside := Coordinate{Latitude: 10.5, Longitude: 122.5}
	outsideLeft := Coordinate{Latitude: 10.5, Longitude: 121.5}
	outsideRight := Coordinate{Latitude: 10.5, Longitude: 123.5}
	if conflict := FirstEndpointConflict(inside, outsideRight, []Restriction{restriction}); conflict == nil || conflict.ID != restriction.ID {
		t.Fatalf("restricted driving endpoint was not blocked: %#v", conflict)
	}
	if conflict := FirstRouteConflict([]Coordinate{outsideLeft, outsideRight}, []Restriction{restriction}); conflict == nil || conflict.ID != restriction.ID {
		t.Fatalf("route crossing restricted driving area was not blocked: %#v", conflict)
	}
}
