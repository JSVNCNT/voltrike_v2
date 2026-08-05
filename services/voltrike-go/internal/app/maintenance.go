package app

import (
	"context"
	"fmt"
	"time"

	"github.com/voltrike/voltrike-go/internal/core"
)

type MaintenanceBooking struct {
	BookingID          string
	Pickup             core.Coordinate
	PrimaryTodaIDs     []string
	SecondaryTodaIDs   []string
	AllowAnyActiveToda bool
	RequiredSeats      int
	SearchExpiresAt    time.Time
	OfferExpiresAt     time.Time
}

type MaintenanceStore interface {
	ListMaintenanceBookings(context.Context, time.Time) ([]MaintenanceBooking, error)
	ExpireBookingSearch(context.Context, string, time.Time) (bool, error)
	ExpireCallsAndEscalateSafety(context.Context, time.Time) (map[string]int, error)
}

func (service *Service) RunMaintenance(ctx context.Context) (map[string]any, error) {
	store, ok := service.store.(MaintenanceStore)
	if !ok {
		return nil, fmt.Errorf("%w: maintenance store is not configured", ErrUnavailable)
	}
	dispatchStore, ok := service.store.(BookingDispatchStore)
	if !ok {
		return nil, fmt.Errorf("%w: dispatch store is not configured", ErrUnavailable)
	}
	now := time.Now().UTC()
	bookings, err := store.ListMaintenanceBookings(ctx, now)
	if err != nil {
		return nil, err
	}
	expired, redispatched := 0, 0
	for _, booking := range bookings {
		if !booking.SearchExpiresAt.IsZero() && !booking.SearchExpiresAt.After(now) {
			changed, expireErr := store.ExpireBookingSearch(ctx, booking.BookingID, now)
			if expireErr != nil {
				return nil, expireErr
			}
			if changed {
				expired++
			}
			continue
		}
		if booking.OfferExpiresAt.After(now) {
			continue
		}
		candidates, dispatchErr := service.DispatchCandidates(ctx, DispatchRequest{
			Pickup:             booking.Pickup,
			PrimaryTodaIDs:     booking.PrimaryTodaIDs,
			SecondaryTodaIDs:   booking.SecondaryTodaIDs,
			AllowAnyActiveToda: booking.AllowAnyActiveToda,
			MaximumResults:     5,
			RequiredSeats:      booking.RequiredSeats,
		})
		if dispatchErr != nil {
			continue
		}
		if err := dispatchStore.PublishBookingOffers(ctx, booking.BookingID, candidates, now.Add(55*time.Second)); err == nil {
			redispatched++
		}
	}
	integration, err := store.ExpireCallsAndEscalateSafety(ctx, now)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"bookingSearchesExpired": expired,
		"bookingsRedispatched":   redispatched,
		"callsExpired":           integration["callsExpired"],
		"safetyEscalated":        integration["safetyEscalated"],
	}, nil
}
