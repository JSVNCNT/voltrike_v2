package app

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/voltrike/voltrike-go/internal/config"
	"github.com/voltrike/voltrike-go/internal/core"
)

var (
	ErrInvalidArgument = errors.New("invalid argument")
	ErrUnavailable     = errors.New("unavailable")
	ErrPrecondition    = errors.New("failed precondition")
)

type Policy struct {
	Fare         core.FareConfig
	Geofences    []core.Geofence
	Restrictions []core.Restriction
	Revision     string
	LoadedAt     time.Time
}

type Store interface {
	LoadPolicy(context.Context) (Policy, error)
	ReadDispatchCell(context.Context, string) (map[string]DispatchPresence, error)
}

type DispatchEligibilityStore interface {
	FilterEligibleDispatch(context.Context, []DispatchCandidate, DispatchRequest) ([]DispatchCandidate, error)
}

type RoutesClient interface {
	Routes(context.Context, core.Coordinate, core.Coordinate) ([]ProviderRoute, error)
}

type ProviderRoute struct {
	DistanceMeters   int
	Duration         string
	Polyline         string
	PartiallyIgnored bool
}

type RouteStop struct {
	Sequence int             `json:"sequence"`
	Type     string          `json:"type"`
	Location core.Coordinate `json:"location"`
	Name     string          `json:"name,omitempty"`
	Address  string          `json:"address,omitempty"`
	Final    bool            `json:"final,omitempty"`
}

type RouteLeg struct {
	Sequence          int             `json:"sequence"`
	Origin            core.Coordinate `json:"origin"`
	Destination       core.Coordinate `json:"destination"`
	DistanceMeters    int             `json:"distanceMeters"`
	EstimatedDuration string          `json:"estimatedDuration"`
	EncodedPolyline   string          `json:"encodedPolyline"`
}

type QuoteRequest struct {
	RequestID            string          `json:"requestId"`
	ActorID              string          `json:"actorId"`
	Pickup               core.Coordinate `json:"pickup"`
	Destination          core.Coordinate `json:"destination"`
	RouteStops           []RouteStop     `json:"routeStops,omitempty"`
	AdditionalPassengers int             `json:"additionalPassengers"`
	BaggageCount         int             `json:"baggageCount"`
	IssueToken           bool            `json:"issueToken"`
}

type HighwayRouteAdvisory struct {
	RequestedAvoidHighways            bool   `json:"requestedAvoidHighways"`
	Provider                          string `json:"provider"`
	RouteRestrictionsPartiallyIgnored bool   `json:"routeRestrictionsPartiallyIgnored"`
	Status                            string `json:"status"`
	ConfirmedViolation                bool   `json:"confirmedViolation"`
}

type Quote struct {
	DistanceMeters               int                  `json:"distanceMeters"`
	EstimatedDuration            string               `json:"estimatedDuration"`
	EstimatedFare                float64              `json:"estimatedFare"`
	FareSnapshot                 core.FareConfig      `json:"fareSnapshot"`
	FareVersion                  int                  `json:"fareVersion"`
	FareBreakdown                core.FareBreakdown   `json:"fareBreakdown"`
	IsOutsideToda                bool                 `json:"isOutsideToda"`
	Coverage                     core.Coverage        `json:"coverage"`
	CoveragePolicyVersion        int                  `json:"coveragePolicyVersion"`
	RoutePolicyVersion           int                  `json:"routePolicyVersion"`
	AuthoritativeRoutePolyline   string               `json:"authoritativeRoutePolyline"`
	RouteLegs                    []RouteLeg           `json:"routeLegs,omitempty"`
	AvoidedRouteRestrictionIDs   []string             `json:"avoidedRouteRestrictionIds"`
	AvoidedRouteRestrictionNames []string             `json:"avoidedRouteRestrictionNames"`
	RouteRestrictionIDsChecked   []string             `json:"routeRestrictionIdsChecked"`
	HighwayRouteAdvisory         HighwayRouteAdvisory `json:"highwayRouteAdvisory"`
	PolicyRevision               string               `json:"policyRevision"`
	ExpiresAt                    time.Time            `json:"expiresAt"`
}

type QuoteResponse struct {
	Quote      Quote  `json:"quote"`
	QuoteToken string `json:"quoteToken,omitempty"`
}

type QuoteTokenRequest struct {
	ActorID              string          `json:"actorId"`
	Pickup               core.Coordinate `json:"pickup"`
	Destination          core.Coordinate `json:"destination"`
	RouteStops           []RouteStop     `json:"routeStops,omitempty"`
	AdditionalPassengers int             `json:"additionalPassengers"`
	BaggageCount         int             `json:"baggageCount"`
	QuoteToken           string          `json:"quoteToken"`
}

type DispatchPresence struct {
	DriverID                 string  `json:"driverId"`
	Latitude                 float64 `json:"latitude"`
	Longitude                float64 `json:"longitude"`
	Timestamp                int64   `json:"timestamp"`
	Accuracy                 float64 `json:"accuracy"`
	Online                   bool    `json:"online"`
	Available                bool    `json:"available"`
	TodaID                   string  `json:"todaId"`
	DailyAwards              int     `json:"dailyAwards"`
	CompletedAssignments     int     `json:"completedAssignments"`
	DriverFaultCancellations int     `json:"driverFaultCancellations"`
	Rating                   float64 `json:"rating"`
	RatingCount              int     `json:"ratingCount"`
}

type DispatchRequest struct {
	Pickup             core.Coordinate `json:"pickup"`
	PrimaryTodaIDs     []string        `json:"primaryTodaIds"`
	SecondaryTodaIDs   []string        `json:"secondaryTodaIds"`
	AllowAnyActiveToda bool            `json:"allowAnyActiveToda"`
	MaximumResults     int             `json:"maximumResults"`
	RequiredSeats      int             `json:"requiredSeats"`
}

type DispatchCandidate struct {
	DriverID         string  `json:"driverId"`
	TodaID           string  `json:"todaId"`
	DistanceMeters   int     `json:"distanceMeters"`
	ServicePriority  int     `json:"servicePriority"`
	DailyAwards      int     `json:"dailyAwards"`
	ReliabilityScore float64 `json:"reliabilityScore"`
	QualityScore     float64 `json:"qualityScore"`
}

type Service struct {
	cfg         config.Config
	store       Store
	routes      RoutesClient
	cacheMu     sync.Mutex
	cached      *Policy
	cacheHits   uint64
	cacheMisses uint64
	aead        cipher.AEAD
}

func NewService(cfg config.Config, store Store) (*Service, error) {
	service := &Service{cfg: cfg, store: store, routes: NewGoogleRoutesClient(cfg.GoogleRoutesAPIKey, cfg.RequestTimeout)}
	if len(cfg.QuoteEncryptionKey) > 0 {
		block, err := aes.NewCipher(cfg.QuoteEncryptionKey)
		if err != nil {
			return nil, fmt.Errorf("create quote cipher: %w", err)
		}
		aead, err := cipher.NewGCM(block)
		if err != nil {
			return nil, fmt.Errorf("create quote AEAD: %w", err)
		}
		service.aead = aead
	}
	return service, nil
}

func (service *Service) InvalidatePolicy() {
	service.cacheMu.Lock()
	defer service.cacheMu.Unlock()
	service.cached = nil
}

func (service *Service) Quote(ctx context.Context, request QuoteRequest) (QuoteResponse, error) {
	if strings.TrimSpace(request.ActorID) == "" || len(request.ActorID) > 128 {
		return QuoteResponse{}, fmt.Errorf("%w: actorId is required", ErrInvalidArgument)
	}
	stops, err := normalizeRouteStops(request.Pickup, request.Destination, request.RouteStops)
	if err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	request.Pickup, request.Destination, request.RouteStops = stops[0].Location, stops[len(stops)-1].Location, stops
	if request.AdditionalPassengers < 0 || request.AdditionalPassengers > 3 || request.BaggageCount < 0 || request.BaggageCount > 1 {
		return QuoteResponse{}, fmt.Errorf("%w: passenger or baggage count is invalid", ErrInvalidArgument)
	}
	policy, err := service.policy(ctx)
	if err != nil {
		return QuoteResponse{}, err
	}
	coordinates := make([]core.Coordinate, 0, len(stops))
	destinations := make([]core.Coordinate, 0, len(stops)-1)
	for index, stop := range stops {
		coordinates = append(coordinates, stop.Location)
		if index > 0 {
			destinations = append(destinations, stop.Location)
		}
	}
	if conflict := core.FirstEndpointConflictStops(coordinates, policy.Restrictions); conflict != nil {
		return QuoteResponse{}, fmt.Errorf("%w: E-trikes cannot pick up, drop off, or travel through %s", ErrPrecondition, fallbackName(conflict.Name, "this restricted area"))
	}
	coverage, err := core.ClassifyCoverageStops(policy.Geofences, request.Pickup, destinations)
	if err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	avoidedIDs, avoidedNames := map[string]struct{}{}, map[string]struct{}{}
	legs := make([]RouteLeg, 0, len(stops)-1)
	combinedPoints := make([]core.Coordinate, 0, 256)
	totalDistance, totalDurationSeconds := 0, 0
	partiallyIgnored := false
	for index := 0; index < len(stops)-1; index++ {
		origin, destination := stops[index].Location, stops[index+1].Location
		candidate, points, routeErr := service.safeRoute(ctx, origin, destination, policy.Restrictions, avoidedIDs, avoidedNames)
		if routeErr != nil {
			return QuoteResponse{}, fmt.Errorf("%w: route leg %d: %v", ErrPrecondition, index+1, routeErr)
		}
		if len(combinedPoints) > 0 && len(points) > 0 {
			points = points[1:]
		}
		combinedPoints = append(combinedPoints, points...)
		totalDistance += candidate.DistanceMeters
		totalDurationSeconds += durationSeconds(candidate.Duration)
		partiallyIgnored = partiallyIgnored || candidate.PartiallyIgnored
		legs = append(legs, RouteLeg{Sequence: index, Origin: origin, Destination: destination, DistanceMeters: candidate.DistanceMeters, EstimatedDuration: candidate.Duration, EncodedPolyline: candidate.Polyline})
	}
	combinedPolyline, err := core.EncodePolyline(combinedPoints)
	if err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: combine route geometry: %v", ErrUnavailable, err)
	}
	advisory := HighwayRouteAdvisory{RequestedAvoidHighways: true, Provider: "google_routes", RouteRestrictionsPartiallyIgnored: partiallyIgnored, ConfirmedViolation: false, Status: "avoidance_not_reported_ignored"}
	if partiallyIgnored {
		advisory.Status = "possibly_ignored"
	}
	fareSnapshot := core.SnapshotFare(policy.Fare)
	quote := Quote{
		DistanceMeters: totalDistance, EstimatedDuration: fmt.Sprintf("%ds", totalDurationSeconds), FareSnapshot: fareSnapshot, FareVersion: fareSnapshot.Version,
		IsOutsideToda: coverage.IsOutsideToda, Coverage: coverage, CoveragePolicyVersion: 4, RoutePolicyVersion: 5,
		AuthoritativeRoutePolyline: combinedPolyline, RouteLegs: legs, AvoidedRouteRestrictionIDs: sorted(avoidedIDs), AvoidedRouteRestrictionNames: sorted(avoidedNames),
		RouteRestrictionIDsChecked: activeRestrictionIDs(policy.Restrictions), HighwayRouteAdvisory: advisory, PolicyRevision: policy.Revision,
		ExpiresAt: time.Now().UTC().Add(75 * time.Second),
	}
	quote.FareBreakdown = core.CalculateFareForDropoffs(quote.FareSnapshot, quote.DistanceMeters, request.AdditionalPassengers, request.BaggageCount, len(stops)-1, quote.IsOutsideToda)
	quote.EstimatedFare = quote.FareBreakdown.Total
	return service.issueQuote(request, quote)
}

func (service *Service) safeRoute(ctx context.Context, origin, destination core.Coordinate, restrictions []core.Restriction, avoidedIDs, avoidedNames map[string]struct{}) (ProviderRoute, []core.Coordinate, error) {
	routes, err := service.routes.Routes(ctx, origin, destination)
	if err != nil {
		return ProviderRoute{}, nil, err
	}
	var fallback *ProviderRoute
	var fallbackPoints []core.Coordinate
	for _, candidate := range routes {
		if candidate.DistanceMeters <= 0 || candidate.Polyline == "" {
			continue
		}
		points, decodeErr := core.DecodePolyline(candidate.Polyline)
		if decodeErr != nil || len(points) < 2 {
			continue
		}
		blocked := core.FirstRouteConflict(points, restrictions)
		if blocked == nil {
			blocked = core.FirstHighwayConflict(points, restrictions)
		}
		if blocked != nil {
			if blocked.ID != "" {
				avoidedIDs[blocked.ID] = struct{}{}
			}
			if blocked.Name != "" {
				avoidedNames[blocked.Name] = struct{}{}
			}
			continue
		}
		if !candidate.PartiallyIgnored {
			return candidate, points, nil
		}
		if fallback == nil {
			copy := candidate
			fallback = &copy
			fallbackPoints = points
		}
	}
	if fallback != nil {
		return *fallback, fallbackPoints, nil
	}
	return ProviderRoute{}, nil, errors.New("no permitted e-trike route is available")
}

func (service *Service) ConsumeQuote(ctx context.Context, request QuoteTokenRequest) (Quote, error) {
	if service.aead == nil {
		return Quote{}, fmt.Errorf("%w: quote tokens are not configured", ErrUnavailable)
	}
	if strings.TrimSpace(request.ActorID) == "" || request.QuoteToken == "" {
		return Quote{}, fmt.Errorf("%w: quote token and actor are required", ErrInvalidArgument)
	}
	stops, err := normalizeRouteStops(request.Pickup, request.Destination, request.RouteStops)
	if err != nil {
		return Quote{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	request.Pickup, request.Destination, request.RouteStops = stops[0].Location, stops[len(stops)-1].Location, stops
	payload, err := service.openToken(request.QuoteToken)
	if err != nil {
		return Quote{}, fmt.Errorf("%w: quote token is invalid", ErrPrecondition)
	}
	if payload.ActorID != request.ActorID || payload.InputHash != quoteInputHash(request.ActorID, request.Pickup, request.Destination, request.RouteStops, request.AdditionalPassengers, request.BaggageCount) {
		return Quote{}, fmt.Errorf("%w: quote token does not match this booking", ErrPrecondition)
	}
	if time.Now().UTC().After(payload.Quote.ExpiresAt) {
		return Quote{}, fmt.Errorf("%w: quote has expired", ErrPrecondition)
	}
	policy, err := service.policy(ctx)
	if err != nil {
		return Quote{}, err
	}
	if policy.Revision != payload.Quote.PolicyRevision {
		return Quote{}, fmt.Errorf("%w: quote policy changed; request a new quote", ErrPrecondition)
	}
	return payload.Quote, nil
}

func (service *Service) DispatchCandidates(ctx context.Context, request DispatchRequest) ([]DispatchCandidate, error) {
	if _, err := core.RequireCoordinate(request.Pickup, "Pickup"); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	limit := request.MaximumResults
	if limit <= 0 || limit > service.cfg.MaximumDispatchResults {
		limit = service.cfg.MaximumDispatchResults
	}
	cellKeys := surroundingCells(request.Pickup, service.cfg.DispatchCellDegrees)
	byID := map[string]DispatchPresence{}
	for _, cell := range cellKeys {
		entries, err := service.store.ReadDispatchCell(ctx, cell)
		if err != nil {
			return nil, fmt.Errorf("%w: read dispatch cell: %v", ErrUnavailable, err)
		}
		for id, entry := range entries {
			if entry.DriverID == "" {
				entry.DriverID = id
			}
			if entry.DriverID != "" {
				byID[entry.DriverID] = entry
			}
		}
	}
	now := time.Now().UnixMilli()
	_, hasAuthoritativeEligibility := service.store.(DispatchEligibilityStore)
	result := make([]DispatchCandidate, 0, len(byID))
	for _, presence := range byID {
		location := core.Coordinate{Latitude: presence.Latitude, Longitude: presence.Longitude}
		if !presence.Online || !location.Valid() || presence.Timestamp <= 0 || now-presence.Timestamp > 35000 || presence.Timestamp > now+10000 || presence.Accuracy < 0 || presence.Accuracy > 100 {
			continue
		}
		todaIDs := append(request.PrimaryTodaIDs, request.SecondaryTodaIDs...)
		if !hasAuthoritativeEligibility {
			if len(todaIDs) > 0 && !presence.Available {
				continue
			}
			if len(todaIDs) > 0 && !request.AllowAnyActiveToda && !containsString(todaIDs, presence.TodaID) {
				continue
			}
		}
		distance := core.HaversineMeters(request.Pickup, location)
		if distance > service.cfg.DispatchRadiusMeters {
			continue
		}
		result = append(result, DispatchCandidate{DriverID: presence.DriverID, DistanceMeters: int(math.Round(distance))})
	}
	if eligibility, ok := service.store.(DispatchEligibilityStore); ok {
		filtered, err := eligibility.FilterEligibleDispatch(ctx, result, request)
		if err != nil {
			return nil, fmt.Errorf("%w: filter dispatch eligibility: %v", ErrUnavailable, err)
		}
		result = filtered
	}
	sort.Slice(result, func(left, right int) bool { return compareCandidate(result[left], result[right]) < 0 })
	return selectDispatchBatch(result, limit), nil
}

func containsString(values []string, target string) bool {
	if target == "" {
		return false
	}
	for _, value := range values {
		if strings.TrimSpace(value) == target {
			return true
		}
	}
	return false
}

func (service *Service) policy(ctx context.Context) (Policy, error) {
	service.cacheMu.Lock()
	if service.cached != nil && time.Since(service.cached.LoadedAt) < service.cfg.PolicyCacheTTL {
		policy := *service.cached
		service.cacheHits++
		service.cacheMu.Unlock()
		return policy, nil
	}
	service.cacheMisses++
	service.cacheMu.Unlock()
	loaded, err := service.store.LoadPolicy(ctx)
	if err != nil {
		return Policy{}, fmt.Errorf("%w: load policy: %v", ErrUnavailable, err)
	}
	if loaded.Revision == "" {
		return Policy{}, fmt.Errorf("%w: empty policy revision", ErrUnavailable)
	}
	loaded.LoadedAt = time.Now().UTC()
	service.cacheMu.Lock()
	service.cached = &loaded
	service.cacheMu.Unlock()
	return loaded, nil
}

type quoteTokenPayload struct {
	ActorID   string `json:"actorId"`
	InputHash string `json:"inputHash"`
	Quote     Quote  `json:"quote"`
}

func (service *Service) issueQuote(request QuoteRequest, quote Quote) (QuoteResponse, error) {
	response := QuoteResponse{Quote: quote}
	if !request.IssueToken {
		return response, nil
	}
	if service.aead == nil {
		return QuoteResponse{}, fmt.Errorf("%w: quote tokens are not configured", ErrUnavailable)
	}
	payload := quoteTokenPayload{ActorID: request.ActorID, InputHash: quoteInputHash(request.ActorID, request.Pickup, request.Destination, request.RouteStops, request.AdditionalPassengers, request.BaggageCount), Quote: quote}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return QuoteResponse{}, fmt.Errorf("marshal quote token: %w", err)
	}
	nonce := make([]byte, service.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return QuoteResponse{}, fmt.Errorf("random quote nonce: %w", err)
	}
	response.QuoteToken = base64.RawURLEncoding.EncodeToString(append(nonce, service.aead.Seal(nil, nonce, encoded, nil)...))
	return response, nil
}

func (service *Service) openToken(token string) (quoteTokenPayload, error) {
	encoded, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(encoded) < service.aead.NonceSize() {
		return quoteTokenPayload{}, errors.New("invalid token")
	}
	plain, err := service.aead.Open(nil, encoded[:service.aead.NonceSize()], encoded[service.aead.NonceSize():], nil)
	if err != nil {
		return quoteTokenPayload{}, err
	}
	var payload quoteTokenPayload
	if err := json.Unmarshal(plain, &payload); err != nil {
		return quoteTokenPayload{}, err
	}
	return payload, nil
}

func quoteInputHash(actor string, pickup, destination core.Coordinate, stops []RouteStop, passengers, baggage int) string {
	normalized, err := normalizeRouteStops(pickup, destination, stops)
	if err != nil {
		return ""
	}
	parts := []string{actor}
	for _, stop := range normalized {
		parts = append(parts, fmt.Sprintf("%d:%s:%.6f:%.6f", stop.Sequence, stop.Type, stop.Location.Latitude, stop.Location.Longitude))
	}
	parts = append(parts, fmt.Sprintf("%d", passengers), fmt.Sprintf("%d", baggage))
	data := strings.Join(parts, "|")
	return fmt.Sprintf("%x", sha256.Sum256([]byte(data)))
}

func normalizeRouteStops(pickup, destination core.Coordinate, raw []RouteStop) ([]RouteStop, error) {
	if len(raw) == 0 {
		raw = []RouteStop{{Type: "pickup", Location: pickup}, {Type: "dropoff", Location: destination, Final: true}}
	}
	if len(raw) < 2 || len(raw) > 3 {
		return nil, errors.New("a booking must contain one pickup and one or two drop-offs")
	}
	result := make([]RouteStop, len(raw))
	for index, item := range raw {
		label := "Destination"
		expectedType := "dropoff"
		if index == 0 {
			label, expectedType = "Pickup", "pickup"
		}
		if _, err := core.RequireCoordinate(item.Location, label); err != nil {
			return nil, err
		}
		if item.Type != "" && item.Type != expectedType {
			return nil, fmt.Errorf("route stop %d must be %s", index, expectedType)
		}
		item.Sequence, item.Type, item.Final = index, expectedType, index == len(raw)-1
		item.Name, item.Address = strings.TrimSpace(item.Name), strings.TrimSpace(item.Address)
		result[index] = item
	}
	if pickup.Valid() && core.HaversineMeters(pickup, result[0].Location) > 2 {
		return nil, errors.New("pickup does not match the first route stop")
	}
	if destination.Valid() && core.HaversineMeters(destination, result[len(result)-1].Location) > 2 {
		return nil, errors.New("destination does not match the final route stop")
	}
	return result, nil
}

func durationSeconds(value string) int {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "s")
	seconds, err := strconv.ParseFloat(trimmed, 64)
	if err != nil || seconds < 0 {
		return 0
	}
	return int(math.Ceil(seconds))
}

func activeRestrictionIDs(restrictions []core.Restriction) []string {
	result := make([]string, 0, len(restrictions))
	for _, item := range restrictions {
		if item.IsActive && item.ID != "" {
			result = append(result, item.ID)
		}
	}
	sort.Strings(result)
	return result
}
func fallbackName(value, fallback string) string {
	if strings.TrimSpace(value) != "" {
		return value
	}
	return fallback
}
func sorted(values map[string]struct{}) []string {
	result := make([]string, 0, len(values))
	for value := range values {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}
func compareCandidate(left, right DispatchCandidate) int {
	if left.ServicePriority != right.ServicePriority {
		return left.ServicePriority - right.ServicePriority
	}
	if left.DistanceMeters/100 != right.DistanceMeters/100 {
		return left.DistanceMeters/100 - right.DistanceMeters/100
	}
	if left.DailyAwards != right.DailyAwards {
		return left.DailyAwards - right.DailyAwards
	}
	if left.ReliabilityScore != right.ReliabilityScore {
		if left.ReliabilityScore > right.ReliabilityScore {
			return -1
		}
		return 1
	}
	if left.QualityScore != right.QualityScore {
		if left.QualityScore > right.QualityScore {
			return -1
		}
		return 1
	}
	if left.DistanceMeters != right.DistanceMeters {
		return left.DistanceMeters - right.DistanceMeters
	}
	return strings.Compare(left.DriverID, right.DriverID)
}

// selectDispatchBatch keeps the normal service-tier and fairness ordering while
// reserving one nearby secondary and fallback candidate when those tiers exist.
// This prevents a dense primary TODA from completely starving mutual-aid
// drivers, without changing which candidates rank first inside each tier.
func selectDispatchBatch(ordered []DispatchCandidate, limit int) []DispatchCandidate {
	if limit <= 0 || len(ordered) == 0 {
		return []DispatchCandidate{}
	}
	if len(ordered) <= limit {
		return ordered
	}
	reserved := make([]DispatchCandidate, 0, 2)
	reservedIDs := map[string]bool{}
	for _, priority := range []int{1, 2} {
		var nearest *DispatchCandidate
		for index := range ordered {
			candidate := ordered[index]
			if candidate.ServicePriority != priority {
				continue
			}
			if nearest == nil || candidate.DistanceMeters < nearest.DistanceMeters ||
				(candidate.DistanceMeters == nearest.DistanceMeters && compareCandidate(candidate, *nearest) < 0) {
				copy := candidate
				nearest = &copy
			}
		}
		if nearest != nil && len(reserved) < limit {
			reserved = append(reserved, *nearest)
			reservedIDs[nearest.DriverID] = true
		}
	}
	selected := make([]DispatchCandidate, 0, limit)
	for _, candidate := range ordered {
		if len(selected) >= limit-len(reserved) {
			break
		}
		if !reservedIDs[candidate.DriverID] {
			selected = append(selected, candidate)
		}
	}
	selected = append(selected, reserved...)
	sort.Slice(selected, func(left, right int) bool { return compareCandidate(selected[left], selected[right]) < 0 })
	return selected
}
func surroundingCells(point core.Coordinate, size float64) []string {
	lat := int(math.Floor((point.Latitude + 90) / size))
	lng := int(math.Floor((point.Longitude + 180) / size))
	result := make([]string, 0, 9)
	for y := -1; y <= 1; y++ {
		for x := -1; x <= 1; x++ {
			result = append(result, fmt.Sprintf("%d:%d", lat+y, lng+x))
		}
	}
	return result
}
