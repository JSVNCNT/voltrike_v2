package app

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/voltrike/voltrike-go/internal/core"
)

type v2QuoteRequest struct {
	Pickup               core.Coordinate `json:"pickup"`
	Destination          core.Coordinate `json:"destination"`
	AdditionalPassengers int             `json:"additionalPassengers"`
	BaggageCount         int             `json:"baggageCount"`
}

func (server *HTTPServer) v2Principal(request *http.Request) (Principal, bool) {
	principal, ok := principalFromContext(request.Context())
	if !ok {
		return Principal{}, false
	}
	return principal, true
}

func (server *HTTPServer) handleV2Capabilities(writer http.ResponseWriter, _ *http.Request) {
	writeJSON(writer, http.StatusOK, map[string]any{
		"data": map[string]any{
			"apiVersion": 2,
			"features": map[string]bool{
				"quotes":          true,
				"bookings":        true,
				"driverSessions":  true,
				"driverLocations": true,
				"outbox":          true,
			},
		},
	})
}

func (server *HTTPServer) handleV2Me(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data": map[string]any{"uid": principal.UID, "claims": principal.Claims},
	})
}

func (server *HTTPServer) handleV2Quote(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var input v2QuoteRequest
	if !server.decode(writer, request, &input) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.Quote(ctx, QuoteRequest{
		ActorID:              principal.UID,
		Pickup:               input.Pickup,
		Destination:          input.Destination,
		AdditionalPassengers: input.AdditionalPassengers,
		BaggageCount:         input.BaggageCount,
		IssueToken:           true,
	})
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data":     result,
		"revision": result.Quote.PolicyRevision,
	})
}

func (server *HTTPServer) handleV2CreateBooking(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var command CreateBookingCommand
	if !server.decode(writer, request, &command) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.CreateBooking(ctx, principal, command)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusCreated, map[string]any{"data": result.Data, "bookingId": result.ID})
}

func (server *HTTPServer) handleV2GetBooking(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.GetBooking(ctx, principal, request.PathValue("bookingId"))
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result.Data, "bookingId": result.ID})
}

func (server *HTTPServer) handleV2AdminBookings(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	query := request.URL.Query()
	pageSize := 25
	if raw := query.Get("pageSize"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			pageSize = parsed
		}
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.ListAdminBookings(ctx, principal, query.Get("cursor"), query.Get("search"), pageSize)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, result)
}

func (server *HTTPServer) handleV2TransitionBooking(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var command TransitionBookingCommand
	if !server.decode(writer, request, &command) {
		return
	}
	command.BookingID = request.PathValue("bookingId")
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.TransitionBooking(ctx, principal, command)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result.Data, "bookingId": result.ID})
}

func (server *HTTPServer) handleV2CreateSession(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var command CreateDriverSessionCommand
	if !server.decode(writer, request, &command) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.CreateDriverSession(ctx, principal, command)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusCreated, map[string]any{"data": result.Data, "sessionId": result.ID})
}

func (server *HTTPServer) handleV2Heartbeat(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var command DriverHeartbeatCommand
	if !server.decode(writer, request, &command) {
		return
	}
	command.SessionID = request.PathValue("sessionId")
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.HeartbeatDriverSession(ctx, principal, command)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result.Data, "sessionId": result.ID})
}

type v2LocationRequest struct {
	LeaseGeneration int64   `json:"leaseGeneration"`
	SampleSequence  uint64  `json:"sampleSequence"`
	Latitude        float64 `json:"latitude"`
	Longitude       float64 `json:"longitude"`
	Accuracy        float64 `json:"accuracy"`
	ObservedAt      string  `json:"observedAt"`
	Online          bool    `json:"online"`
	Available       bool    `json:"available"`
	TodaID          string  `json:"todaId"`
}

func (server *HTTPServer) handleV2Location(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var input v2LocationRequest
	if !server.decode(writer, request, &input) {
		return
	}
	observedAt := time.Time{}
	if strings.TrimSpace(input.ObservedAt) != "" {
		parsed, err := time.Parse(time.RFC3339Nano, input.ObservedAt)
		if err != nil {
			writeJSON(writer, http.StatusBadRequest, errorBody("invalid_argument", "observedAt must be RFC3339."))
			return
		}
		observedAt = parsed
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	err := server.service.UpdateDriverLocation(ctx, principal, DriverLocationCommand{
		SessionID:       request.PathValue("sessionId"),
		LeaseGeneration: input.LeaseGeneration,
		SampleSequence:  input.SampleSequence,
		Latitude:        input.Latitude,
		Longitude:       input.Longitude,
		Accuracy:        input.Accuracy,
		ObservedAt:      observedAt,
		Online:          input.Online,
		Available:       input.Available,
		TodaID:          input.TodaID,
	})
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusAccepted, map[string]any{"accepted": true, "sampleSequence": input.SampleSequence})
}

func (server *HTTPServer) handleV2Operation(writer http.ResponseWriter, request *http.Request) {
	principal, ok := server.v2Principal(request)
	if !ok {
		writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Authentication is required."))
		return
	}
	var input struct {
		CommandID string         `json:"commandId"`
		Payload   map[string]any `json:"payload"`
	}
	if !server.decode(writer, request, &input) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.ExecuteOperation(ctx, principal, OperationCommand{
		Name: request.PathValue("operation"), CommandID: input.CommandID, Payload: input.Payload,
	})
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result})
}
