package app

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/voltrike/voltrike-go/internal/core"
)

// Principal is the authenticated Firebase identity attached to a request.
// Claims are hints; sensitive role and suspension checks belong to the domain
// store and are intentionally not trusted from request JSON.
type Principal struct {
	UID    string
	Claims map[string]any
}

type IdentityVerifier interface {
	VerifyIDToken(context.Context, string) (Principal, error)
	VerifyAppCheck(string) error
}

type BookingRecord struct {
	ID   string         `json:"bookingId"`
	Data map[string]any `json:"data"`
}

type DriverSessionRecord struct {
	ID   string         `json:"sessionId"`
	Data map[string]any `json:"data"`
}

type AdminPage struct {
	Items      []map[string]any `json:"items"`
	NextCursor string           `json:"nextCursor,omitempty"`
}

type OperationCommand struct {
	Name      string         `json:"-"`
	CommandID string         `json:"commandId,omitempty"`
	Payload   map[string]any `json:"payload,omitempty"`
}

type CreateBookingCommand struct {
	BookingID            string          `json:"bookingId"`
	OperationID          string          `json:"commandId"`
	Pickup               core.Coordinate `json:"pickup"`
	Destination          core.Coordinate `json:"destination"`
	RouteStops           []RouteStop     `json:"routeStops,omitempty"`
	PickupName           string          `json:"pickupName"`
	DestinationName      string          `json:"destinationName"`
	PickupAddress        string          `json:"pickupAddress"`
	DestinationAddress   string          `json:"destinationAddress"`
	AdditionalPassengers int             `json:"additionalPassengers"`
	BaggageCount         int             `json:"baggageCount"`
	RequestedVehicleType string          `json:"requestedVehicleType"`
	PassengerNote        string          `json:"passengerNote,omitempty"`
	QuoteToken           string          `json:"quoteToken"`
}

type TransitionBookingCommand struct {
	BookingID        string `json:"bookingId"`
	CommandID        string `json:"commandId"`
	Action           string `json:"action"`
	ExpectedRevision int    `json:"expectedRevision"`
	DriverID         string `json:"driverId,omitempty"`
	ReasonCode       string `json:"reasonCode,omitempty"`
	ReasonDetail     string `json:"reasonDetail,omitempty"`
	StopIndex        int    `json:"stopIndex,omitempty"`
}

type CreateDriverSessionCommand struct {
	SessionID  string `json:"sessionId"`
	DeviceID   string `json:"deviceId"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
	Takeover   bool   `json:"takeover"`
}

type DriverHeartbeatCommand struct {
	SessionID       string `json:"sessionId"`
	LeaseGeneration int64  `json:"leaseGeneration"`
	SampleSequence  uint64 `json:"sampleSequence"`
}

type DriverLocationCommand struct {
	SessionID       string    `json:"sessionId"`
	LeaseGeneration int64     `json:"leaseGeneration"`
	SampleSequence  uint64    `json:"sampleSequence"`
	Latitude        float64   `json:"latitude"`
	Longitude       float64   `json:"longitude"`
	Accuracy        float64   `json:"accuracy"`
	ObservedAt      time.Time `json:"observedAt"`
	Online          bool      `json:"online"`
	Available       bool      `json:"available"`
	TodaID          string    `json:"todaId"`
}

type DomainStore interface {
	CreateBooking(context.Context, Principal, CreateBookingCommand, Quote) (BookingRecord, error)
	GetBooking(context.Context, Principal, string) (BookingRecord, error)
	TransitionBooking(context.Context, Principal, TransitionBookingCommand) (BookingRecord, error)
	CreateDriverSession(context.Context, Principal, CreateDriverSessionCommand) (DriverSessionRecord, error)
	HeartbeatDriverSession(context.Context, Principal, DriverHeartbeatCommand) (DriverSessionRecord, error)
	UpdateDriverLocation(context.Context, Principal, DriverLocationCommand) error
	ListAdminBookings(context.Context, Principal, string, string, int) (AdminPage, error)
}

type OperationStore interface {
	ExecuteOperation(context.Context, Principal, OperationCommand) (map[string]any, error)
}

type BookingDispatchStore interface {
	PublishBookingOffers(context.Context, string, []DispatchCandidate, time.Time) error
}

// BookingCreateLookupStore lets a durable retry return the booking committed
// by its first attempt before the short-lived quote token is validated again.
// The lookup must verify both ownership and the original create payload.
type BookingCreateLookupStore interface {
	FindExistingBookingForCreate(context.Context, Principal, CreateBookingCommand) (BookingRecord, bool, error)
}

func (service *Service) ExecuteOperation(ctx context.Context, principal Principal, command OperationCommand) (map[string]any, error) {
	if strings.TrimSpace(principal.UID) == "" || strings.TrimSpace(command.Name) == "" {
		return nil, fmt.Errorf("%w: authenticated user and operation are required", ErrInvalidArgument)
	}
	commandID := strings.TrimSpace(command.CommandID)
	if commandID == "" || len(commandID) > 128 || strings.ContainsAny(commandID, "/\\.#$[]") {
		return nil, fmt.Errorf("%w: a safe commandId is required", ErrInvalidArgument)
	}
	command.CommandID = commandID
	if command.Payload == nil {
		command.Payload = map[string]any{}
	}
	store, ok := service.store.(OperationStore)
	if !ok {
		return nil, fmt.Errorf("%w: operation store is not configured", ErrUnavailable)
	}
	return store.ExecuteOperation(ctx, principal, command)
}

func (service *Service) ListAdminBookings(ctx context.Context, principal Principal, cursor, search string, pageSize int) (AdminPage, error) {
	if strings.TrimSpace(principal.UID) == "" {
		return AdminPage{}, fmt.Errorf("%w: authenticated user is required", ErrInvalidArgument)
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 25
	}
	store, err := domainStore(service)
	if err != nil {
		return AdminPage{}, err
	}
	return store.ListAdminBookings(ctx, principal, cursor, search, pageSize)
}

func domainStore(service *Service) (DomainStore, error) {
	store, ok := service.store.(DomainStore)
	if !ok {
		return nil, fmt.Errorf("%w: domain store is not configured", ErrUnavailable)
	}
	return store, nil
}

func (service *Service) CreateBooking(ctx context.Context, principal Principal, command CreateBookingCommand) (BookingRecord, error) {
	if strings.TrimSpace(principal.UID) == "" {
		return BookingRecord{}, fmt.Errorf("%w: authenticated user is required", ErrInvalidArgument)
	}
	if strings.TrimSpace(command.BookingID) == "" || len(command.BookingID) > 128 {
		return BookingRecord{}, fmt.Errorf("%w: bookingId is required", ErrInvalidArgument)
	}
	if command.QuoteToken == "" {
		return BookingRecord{}, fmt.Errorf("%w: quoteToken is required", ErrInvalidArgument)
	}
	stops, normalizeErr := normalizeRouteStops(command.Pickup, command.Destination, command.RouteStops)
	if normalizeErr != nil {
		return BookingRecord{}, fmt.Errorf("%w: %v", ErrInvalidArgument, normalizeErr)
	}
	command.Pickup, command.Destination, command.RouteStops = stops[0].Location, stops[len(stops)-1].Location, stops
	command.RequestedVehicleType = resolvedRideType(command.RequestedVehicleType, command.AdditionalPassengers+1)
	if command.RequestedVehicleType == "" || !core.RideTypeCanCarry(command.RequestedVehicleType, command.AdditionalPassengers+1) {
		return BookingRecord{}, fmt.Errorf("%w: requestedVehicleType is invalid for this booking", ErrInvalidArgument)
	}
	command.PassengerNote = strings.TrimSpace(command.PassengerNote)
	if len([]rune(command.PassengerNote)) > 120 {
		return BookingRecord{}, fmt.Errorf("%w: passengerNote must be 120 characters or fewer", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return BookingRecord{}, err
	}
	if lookup, ok := service.store.(BookingCreateLookupStore); ok {
		existing, found, lookupErr := lookup.FindExistingBookingForCreate(ctx, principal, command)
		if lookupErr != nil {
			return BookingRecord{}, lookupErr
		}
		if found {
			return existing, nil
		}
	}
	quote, err := service.ConsumeQuote(ctx, QuoteTokenRequest{
		ActorID:              principal.UID,
		Pickup:               command.Pickup,
		Destination:          command.Destination,
		RouteStops:           command.RouteStops,
		AdditionalPassengers: command.AdditionalPassengers,
		BaggageCount:         command.BaggageCount,
		RequestedVehicleType: command.RequestedVehicleType,
		QuoteToken:           command.QuoteToken,
	})
	if err != nil {
		return BookingRecord{}, err
	}
	record, err := store.CreateBooking(ctx, principal, command, quote)
	if err != nil {
		return BookingRecord{}, err
	}
	dispatchStore, ok := service.store.(BookingDispatchStore)
	if !ok {
		return BookingRecord{}, fmt.Errorf("%w: booking dispatch store is not configured", ErrUnavailable)
	}
	candidates, dispatchErr := service.DispatchCandidates(ctx, DispatchRequest{
		Pickup: command.Pickup, PrimaryTodaIDs: quote.Coverage.PrimaryTodaIDs,
		SecondaryTodaIDs: quote.Coverage.SecondaryTodaIDs, AllowAnyActiveToda: quote.Coverage.AllowAnyActiveToda,
		MaximumResults:       5,
		RequiredSeats:        command.AdditionalPassengers + 1,
		RequestedVehicleType: command.RequestedVehicleType,
	})
	// Booking creation is already committed at this point. Dispatch is a
	// retryable projection and must never turn a successful idempotent create
	// into a client-visible failure that encourages a second booking.
	if dispatchErr != nil {
		slog.Warn("initial booking dispatch failed", "bookingId", command.BookingID, "error", dispatchErr)
	} else if len(candidates) == 0 {
		slog.Info("initial booking dispatch found no eligible drivers", "bookingId", command.BookingID)
	} else if publishErr := dispatchStore.PublishBookingOffers(ctx, command.BookingID, candidates, time.Now().UTC().Add(55*time.Second)); publishErr != nil {
		slog.Warn("publish initial booking offers", "bookingId", command.BookingID, "candidates", len(candidates), "error", publishErr)
	}
	return record, nil
}

func (service *Service) GetBooking(ctx context.Context, principal Principal, bookingID string) (BookingRecord, error) {
	if strings.TrimSpace(bookingID) == "" {
		return BookingRecord{}, fmt.Errorf("%w: bookingId is required", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return BookingRecord{}, err
	}
	return store.GetBooking(ctx, principal, bookingID)
}

func (service *Service) TransitionBooking(ctx context.Context, principal Principal, command TransitionBookingCommand) (BookingRecord, error) {
	if strings.TrimSpace(command.BookingID) == "" || strings.TrimSpace(command.CommandID) == "" {
		return BookingRecord{}, fmt.Errorf("%w: bookingId and commandId are required", ErrInvalidArgument)
	}
	if command.ExpectedRevision < 1 {
		return BookingRecord{}, fmt.Errorf("%w: expectedRevision is required", ErrInvalidArgument)
	}
	if !supportedBookingTransitionAction(command.Action) {
		return BookingRecord{}, fmt.Errorf("%w: unsupported booking action", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return BookingRecord{}, err
	}
	return store.TransitionBooking(ctx, principal, command)
}

func supportedBookingTransitionAction(action string) bool {
	switch action {
	case "accept", "arrived", "start", "advanceStop", "payment", "complete", "cancel", "noShow", "decline", "dispute", "receipt":
		return true
	default:
		return false
	}
}

func (service *Service) CreateDriverSession(ctx context.Context, principal Principal, command CreateDriverSessionCommand) (DriverSessionRecord, error) {
	if strings.TrimSpace(principal.UID) == "" || strings.TrimSpace(command.SessionID) == "" || strings.TrimSpace(command.DeviceID) == "" {
		return DriverSessionRecord{}, fmt.Errorf("%w: driver, session, and device identifiers are required", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return DriverSessionRecord{}, err
	}
	return store.CreateDriverSession(ctx, principal, command)
}

func (service *Service) HeartbeatDriverSession(ctx context.Context, principal Principal, command DriverHeartbeatCommand) (DriverSessionRecord, error) {
	if command.LeaseGeneration < 1 || command.SampleSequence < 1 {
		return DriverSessionRecord{}, fmt.Errorf("%w: leaseGeneration and sampleSequence are required", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return DriverSessionRecord{}, err
	}
	return store.HeartbeatDriverSession(ctx, principal, command)
}

func (service *Service) UpdateDriverLocation(ctx context.Context, principal Principal, command DriverLocationCommand) error {
	if command.LeaseGeneration < 1 || command.SampleSequence < 1 {
		return fmt.Errorf("%w: leaseGeneration and sampleSequence are required", ErrInvalidArgument)
	}
	if !(core.Coordinate{Latitude: command.Latitude, Longitude: command.Longitude}).Valid() {
		return fmt.Errorf("%w: location is invalid", ErrInvalidArgument)
	}
	if command.Accuracy < 0 || command.Accuracy > 500 {
		return fmt.Errorf("%w: accuracy is invalid", ErrInvalidArgument)
	}
	store, err := domainStore(service)
	if err != nil {
		return err
	}
	return store.UpdateDriverLocation(ctx, principal, command)
}
