package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/voltrike/voltrike-go/internal/core"
)

const routesURL = "https://routes.googleapis.com/directions/v2:computeRoutes"

type googleRoutesClient struct {
	apiKey string
	client *http.Client
}

func NewGoogleRoutesClient(apiKey string, timeout time.Duration) RoutesClient {
	return &googleRoutesClient{apiKey: apiKey, client: &http.Client{Timeout: timeout}}
}

func (client *googleRoutesClient) Routes(ctx context.Context, pickup, destination core.Coordinate) ([]ProviderRoute, error) {
	body := map[string]any{
		"origin":      map[string]any{"location": map[string]any{"latLng": map[string]float64{"latitude": pickup.Latitude, "longitude": pickup.Longitude}}},
		"destination": map[string]any{"location": map[string]any{"latLng": map[string]float64{"latitude": destination.Latitude, "longitude": destination.Longitude}}},
		"travelMode":  "DRIVE", "routingPreference": "TRAFFIC_AWARE", "routeModifiers": map[string]bool{"avoidHighways": true}, "computeAlternativeRoutes": true, "languageCode": "en-PH", "units": "METRIC",
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, routesURL, bytes.NewReader(encoded))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Goog-Api-Key", client.apiKey)
	request.Header.Set("X-Goog-FieldMask", "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.travelAdvisory.routeRestrictionsPartiallyIgnored")
	response, err := client.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("Google Routes request: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(response.Body, 512))
		return nil, fmt.Errorf("Google Routes status %d: %s", response.StatusCode, string(raw))
	}
	var decoded struct {
		Routes []struct {
			DistanceMeters int    `json:"distanceMeters"`
			Duration       string `json:"duration"`
			Polyline       struct {
				Encoded string `json:"encodedPolyline"`
			} `json:"polyline"`
			TravelAdvisory struct {
				PartiallyIgnored bool `json:"routeRestrictionsPartiallyIgnored"`
			} `json:"travelAdvisory"`
		} `json:"routes"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(&decoded); err != nil {
		return nil, fmt.Errorf("decode Google Routes response: %w", err)
	}
	result := make([]ProviderRoute, 0, len(decoded.Routes))
	for _, route := range decoded.Routes {
		result = append(result, ProviderRoute{DistanceMeters: route.DistanceMeters, Duration: route.Duration, Polyline: route.Polyline.Encoded, PartiallyIgnored: route.TravelAdvisory.PartiallyIgnored})
	}
	return result, nil
}
