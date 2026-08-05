package app

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/voltrike/voltrike-go/internal/config"
)

type HTTPServer struct {
	cfg      config.Config
	service  *Service
	verifier IdentityVerifier
}

func NewHTTPServer(cfg config.Config, service *Service, verifiers ...IdentityVerifier) *http.Server {
	handler := &HTTPServer{cfg: cfg, service: service}
	if len(verifiers) > 0 {
		handler.verifier = verifiers[0]
	}
	return &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           handler.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       cfg.RequestTimeout + 2*time.Second,
		WriteTimeout:      cfg.RequestTimeout + 2*time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

func (server *HTTPServer) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, http.StatusOK, map[string]any{"status": "ok", "service": "voltrike-api-v2", "version": 2})
	})
	mux.HandleFunc("GET /readyz", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, http.StatusOK, map[string]any{"status": "ready", "service": "voltrike-api-v2", "version": 2})
	})
	mux.HandleFunc("POST /v1/quotes/compute", server.handleQuote)
	mux.HandleFunc("POST /v1/quotes/consume", server.handleConsumeQuote)
	mux.HandleFunc("POST /v1/policy/invalidate", server.handleInvalidatePolicy)
	mux.HandleFunc("POST /v1/dispatch/candidates", server.handleDispatch)
	v2 := http.NewServeMux()
	v2.HandleFunc("GET /api/v2/capabilities", server.handleV2Capabilities)
	v2.HandleFunc("GET /api/v2/me", server.handleV2Me)
	v2.HandleFunc("POST /api/v2/quotes", server.handleV2Quote)
	v2.HandleFunc("POST /api/v2/bookings", server.handleV2CreateBooking)
	v2.HandleFunc("GET /api/v2/bookings/{bookingId}", server.handleV2GetBooking)
	v2.HandleFunc("GET /api/v2/admin/bookings", server.handleV2AdminBookings)
	v2.HandleFunc("POST /api/v2/bookings/{bookingId}/commands", server.handleV2TransitionBooking)
	v2.HandleFunc("POST /api/v2/driver/sessions", server.handleV2CreateSession)
	v2.HandleFunc("POST /api/v2/driver/sessions/{sessionId}/heartbeat", server.handleV2Heartbeat)
	v2.HandleFunc("PUT /api/v2/driver/sessions/{sessionId}/location", server.handleV2Location)
	v2.HandleFunc("POST /api/v2/operations/{operation}", server.handleV2Operation)
	mux.Handle("/api/v2/", server.authenticateV2(v2))
	return server.cors(server.recover(server.authorize(mux)))
}

func (server *HTTPServer) handleQuote(writer http.ResponseWriter, request *http.Request) {
	var input QuoteRequest
	if !server.decode(writer, request, &input) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.Quote(ctx, input)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, result)
}

func (server *HTTPServer) handleConsumeQuote(writer http.ResponseWriter, request *http.Request) {
	var input QuoteTokenRequest
	if !server.decode(writer, request, &input) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.ConsumeQuote(ctx, input)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"quote": result})
}

func (server *HTTPServer) handleInvalidatePolicy(writer http.ResponseWriter, _ *http.Request) {
	server.service.InvalidatePolicy()
	writeJSON(writer, http.StatusOK, map[string]any{"invalidated": true})
}

func (server *HTTPServer) handleDispatch(writer http.ResponseWriter, request *http.Request) {
	var input DispatchRequest
	if !server.decode(writer, request, &input) {
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), server.cfg.RequestTimeout)
	defer cancel()
	result, err := server.service.DispatchCandidates(ctx, input)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"candidates": result})
}

func (server *HTTPServer) decode(writer http.ResponseWriter, request *http.Request, target any) bool {
	request.Body = http.MaxBytesReader(writer, request.Body, server.cfg.MaximumRequestBody)
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeJSON(writer, http.StatusBadRequest, errorBody("invalid_argument", "Request JSON is invalid."))
		return false
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeJSON(writer, http.StatusBadRequest, errorBody("invalid_argument", "Request body must contain one JSON object."))
		return false
	}
	return true
}

func (server *HTTPServer) authorize(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasPrefix(request.URL.Path, "/api/v2/") {
			next.ServeHTTP(writer, request)
			return
		}
		if request.URL.Path == "/healthz" || request.URL.Path == "/readyz" || server.cfg.LocalInternalKey == "" {
			next.ServeHTTP(writer, request)
			return
		}
		supplied := request.Header.Get("X-Voltrike-Internal-Key")
		if subtle.ConstantTimeCompare([]byte(supplied), []byte(server.cfg.LocalInternalKey)) != 1 {
			writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Internal authentication is required."))
			return
		}
		next.ServeHTTP(writer, request)
	})
}

type principalContextKey struct{}

func principalFromContext(ctx context.Context) (Principal, bool) {
	value, ok := ctx.Value(principalContextKey{}).(Principal)
	return value, ok && value.UID != ""
}

func (server *HTTPServer) authenticateV2(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		var principal Principal
		authorization := strings.TrimSpace(request.Header.Get("Authorization"))
		token := strings.TrimSpace(strings.TrimPrefix(authorization, "Bearer "))
		if server.cfg.AllowUnauthenticatedLocal && token == "" {
			principal = Principal{UID: strings.TrimSpace(request.Header.Get("X-Debug-UID"))}
			if principal.UID == "" {
				principal.UID = "local-user"
			}
		} else {
			if server.verifier == nil || token == "" {
				writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Firebase authentication is required."))
				return
			}
			var err error
			principal, err = server.verifier.VerifyIDToken(request.Context(), token)
			if err != nil {
				writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Firebase authentication is invalid."))
				return
			}
		}
		if server.cfg.RequireAppCheck {
			appCheckToken := strings.TrimSpace(request.Header.Get("X-Firebase-AppCheck"))
			if server.verifier == nil || appCheckToken == "" || server.verifier.VerifyAppCheck(appCheckToken) != nil {
				writeJSON(writer, http.StatusUnauthorized, errorBody("unauthenticated", "Firebase App Check is required."))
				return
			}
		}
		next.ServeHTTP(writer, request.WithContext(context.WithValue(request.Context(), principalContextKey{}, principal)))
	})
}

func (server *HTTPServer) recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		defer func() {
			if value := recover(); value != nil {
				slog.Error("recovered HTTP panic", "path", request.URL.Path, "error", fmt.Sprint(value))
				writeJSON(writer, http.StatusInternalServerError, errorBody("internal", "Internal service error."))
			}
		}()
		next.ServeHTTP(writer, request)
	})
}

func (server *HTTPServer) cors(next http.Handler) http.Handler {
	allowed := map[string]struct{}{}
	for _, origin := range strings.Split(server.cfg.AllowedOrigins, ",") {
		origin = strings.TrimSpace(origin)
		if origin != "" {
			allowed[origin] = struct{}{}
		}
	}
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		origin := strings.TrimSpace(request.Header.Get("Origin"))
		if _, ok := allowed[origin]; ok {
			writer.Header().Set("Access-Control-Allow-Origin", origin)
			writer.Header().Set("Vary", "Origin")
			writer.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Firebase-AppCheck")
			writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
		}
		if request.Method == http.MethodOptions {
			writer.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(writer, request)
	})
}

func writeServiceError(writer http.ResponseWriter, err error) {
	status, code := http.StatusInternalServerError, "internal"
	switch {
	case errors.Is(err, ErrInvalidArgument):
		status, code = http.StatusBadRequest, "invalid_argument"
	case errors.Is(err, ErrPrecondition):
		status, code = http.StatusPreconditionFailed, "failed_precondition"
	case errors.Is(err, ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
		status, code = http.StatusServiceUnavailable, "unavailable"
	}
	message := strings.TrimSpace(err.Error())
	for _, prefix := range []string{"invalid argument: ", "failed precondition: ", "unavailable: "} {
		message = strings.TrimPrefix(message, prefix)
	}
	if status == http.StatusInternalServerError {
		slog.Error("Go service request failed", "error", err)
		message = "Internal service error."
	}
	writeJSON(writer, status, errorBody(code, message))
}

func errorBody(code, message string) map[string]any {
	return map[string]any{"error": map[string]string{"code": code, "message": message}}
}

func writeJSON(writer http.ResponseWriter, status int, value any) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.Header().Set("Cache-Control", "no-store")
	writer.WriteHeader(status)
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		slog.Warn("encode HTTP response", "error", err)
	}
}
