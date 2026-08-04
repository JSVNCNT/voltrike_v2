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

type RoutesClient interface {
	Routes(context.Context, core.Coordinate, core.Coordinate) ([]ProviderRoute, error)
}

type ProviderRoute struct {
	DistanceMeters   int
	Duration         string
	Polyline         string
	PartiallyIgnored bool
}

type QuoteRequest struct {
	RequestID            string          `json:"requestId"`
	ActorID              string          `json:"actorId"`
	Pickup               core.Coordinate `json:"pickup"`
	Destination          core.Coordinate `json:"destination"`
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
	if _, err := core.RequireCoordinate(request.Pickup, "Pickup"); err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	if _, err := core.RequireCoordinate(request.Destination, "Destination"); err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	if request.AdditionalPassengers < 0 || request.AdditionalPassengers > 3 || request.BaggageCount < 0 || request.BaggageCount > 1 {
		return QuoteResponse{}, fmt.Errorf("%w: passenger or baggage count is invalid", ErrInvalidArgument)
	}
	policy, err := service.policy(ctx)
	if err != nil {
		return QuoteResponse{}, err
	}
	if conflict := core.FirstEndpointConflict(request.Pickup, request.Destination, policy.Restrictions); conflict != nil {
		return QuoteResponse{}, fmt.Errorf("%w: E-trikes cannot pick up, drop off, or travel through %s", ErrPrecondition, fallbackName(conflict.Name, "this restricted area"))
	}
	coverage, err := core.ClassifyCoverage(policy.Geofences, request.Pickup, request.Destination)
	if err != nil {
		return QuoteResponse{}, fmt.Errorf("%w: %v", ErrInvalidArgument, err)
	}
	routes, err := service.routes.Routes(ctx, request.Pickup, request.Destination)
	if err != nil {
		return QuoteResponse{}, err
	}
	if len(routes) == 0 {
		return QuoteResponse{}, fmt.Errorf("%w: no valid driving route is available", ErrPrecondition)
	}

	avoidedIDs, avoidedNames := map[string]struct{}{}, map[string]struct{}{}
	var fallback *Quote
	for _, candidate := range routes {
		if candidate.DistanceMeters <= 0 || candidate.Polyline == "" {
			continue
		}
		points, err := core.DecodePolyline(candidate.Polyline)
		if err != nil || len(points) < 2 {
			continue
		}
		blocked := core.FirstRouteConflict(points, policy.Restrictions)
		if blocked == nil {
			blocked = core.FirstHighwayConflict(points, policy.Restrictions)
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
		advisory := HighwayRouteAdvisory{RequestedAvoidHighways: true, Provider: "google_routes", RouteRestrictionsPartiallyIgnored: candidate.PartiallyIgnored, ConfirmedViolation: false}
		if candidate.PartiallyIgnored {
			advisory.Status = "possibly_ignored"
		} else {
			advisory.Status = "avoidance_not_reported_ignored"
		}
		quote := Quote{
			DistanceMeters: candidate.DistanceMeters, EstimatedDuration: candidate.Duration, FareSnapshot: core.SnapshotFare(policy.Fare), FareVersion: core.SnapshotFare(policy.Fare).Version,
			IsOutsideToda: coverage.IsOutsideToda, Coverage: coverage, CoveragePolicyVersion: 3, RoutePolicyVersion: 4,
			AuthoritativeRoutePolyline: candidate.Polyline, AvoidedRouteRestrictionIDs: sorted(avoidedIDs), AvoidedRouteRestrictionNames: sorted(avoidedNames),
			RouteRestrictionIDsChecked: activeRestrictionIDs(policy.Restrictions), HighwayRouteAdvisory: advisory, PolicyRevision: policy.Revision,
			ExpiresAt: time.Now().UTC().Add(75 * time.Second),
		}
		quote.FareBreakdown = core.CalculateFare(quote.FareSnapshot, quote.DistanceMeters, request.AdditionalPassengers, request.BaggageCount, quote.IsOutsideToda)
		quote.EstimatedFare = quote.FareBreakdown.Total
		if !candidate.PartiallyIgnored {
			return service.issueQuote(request, quote)
		}
		if fallback == nil {
			fallback = &quote
		}
	}
	if fallback != nil {
		return service.issueQuote(request, *fallback)
	}
	return QuoteResponse{}, fmt.Errorf("%w: no permitted e-trike route is available", ErrPrecondition)
}

func (service *Service) ConsumeQuote(ctx context.Context, request QuoteTokenRequest) (Quote, error) {
	if service.aead == nil {
		return Quote{}, fmt.Errorf("%w: quote tokens are not configured", ErrUnavailable)
	}
	if strings.TrimSpace(request.ActorID) == "" || request.QuoteToken == "" {
		return Quote{}, fmt.Errorf("%w: quote token and actor are required", ErrInvalidArgument)
	}
	payload, err := service.openToken(request.QuoteToken)
	if err != nil {
		return Quote{}, fmt.Errorf("%w: quote token is invalid", ErrPrecondition)
	}
	if payload.ActorID != request.ActorID || payload.InputHash != quoteInputHash(request.ActorID, request.Pickup, request.Destination, request.AdditionalPassengers, request.BaggageCount) {
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
	result := make([]DispatchCandidate, 0, len(byID))
	for _, presence := range byID {
		location := core.Coordinate{Latitude: presence.Latitude, Longitude: presence.Longitude}
		if !presence.Online || !location.Valid() || presence.Timestamp <= 0 || now-presence.Timestamp > 35000 || presence.Timestamp > now+10000 || presence.Accuracy < 0 || presence.Accuracy > 100 {
			continue
		}
		distance := core.HaversineMeters(request.Pickup, location)
		if distance > service.cfg.DispatchRadiusMeters {
			continue
		}
		result = append(result, DispatchCandidate{DriverID: presence.DriverID, DistanceMeters: int(math.Round(distance))})
	}
	sort.Slice(result, func(left, right int) bool { return compareCandidate(result[left], result[right]) < 0 })
	if len(result) > limit {
		result = result[:limit]
	}
	return result, nil
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
	payload := quoteTokenPayload{ActorID: request.ActorID, InputHash: quoteInputHash(request.ActorID, request.Pickup, request.Destination, request.AdditionalPassengers, request.BaggageCount), Quote: quote}
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

func quoteInputHash(actor string, pickup, destination core.Coordinate, passengers, baggage int) string {
	data := fmt.Sprintf("%s|%.6f|%.6f|%.6f|%.6f|%d|%d", actor, pickup.Latitude, pickup.Longitude, destination.Latitude, destination.Longitude, passengers, baggage)
	return fmt.Sprintf("%x", sha256.Sum256([]byte(data)))
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
