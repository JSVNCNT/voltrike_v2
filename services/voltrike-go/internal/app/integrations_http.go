package app

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type accountEmailStore interface {
	RequestPasswordReset(context.Context, string) (map[string]any, error)
}

type notificationStore interface {
	ProcessOutbox(context.Context, string) (map[string]any, error)
	RetryOutbox(context.Context) (map[string]any, error)
}

func (server *HTTPServer) handlePasswordReset(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Email string `json:"email"`
	}
	if !server.decode(writer, request, &input) {
		return
	}
	store, ok := server.service.store.(accountEmailStore)
	if !ok {
		writeServiceError(writer, fmt.Errorf("%w: account email is not configured", ErrUnavailable))
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 25*time.Second)
	defer cancel()
	result, err := store.RequestPasswordReset(ctx, input.Email)
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result})
}

// These routes exist only on the separate IAM-authenticated Cloud Run worker.
// They are never registered by the public Firebase-user-authenticated API.
func (server *HTTPServer) handleOutboxEvent(writer http.ResponseWriter, request *http.Request) {
	if !server.cfg.NotificationsEnabled {
		writeServiceError(writer, fmt.Errorf("%w: notification cutover is not enabled", ErrUnavailable))
		return
	}
	source := "//firestore.googleapis.com/projects/" + server.cfg.ProjectID + "/databases/(default)"
	subject := strings.TrimPrefix(request.Header.Get("Ce-Subject"), "documents/")
	parts := strings.Split(subject, "/")
	if request.Header.Get("Ce-Type") != "google.cloud.firestore.document.v1.created" ||
		request.Header.Get("Ce-Source") != source || request.Header.Get("Ce-Id") == "" ||
		len(parts) != 2 || parts[0] != "outbox" || parts[1] == "" || parts[1] == "." || parts[1] == ".." {
		writeJSON(writer, http.StatusBadRequest, errorBody("invalid_argument", "A project outbox CloudEvent is required."))
		return
	}
	store, ok := server.service.store.(notificationStore)
	if !ok {
		writeServiceError(writer, fmt.Errorf("%w: notification worker is not configured", ErrUnavailable))
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 100*time.Second)
	defer cancel()
	result, err := store.ProcessOutbox(ctx, parts[1])
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result})
}

func (server *HTTPServer) handleWorkerMaintenance(writer http.ResponseWriter, request *http.Request) {
	ctx, cancel := context.WithTimeout(request.Context(), 100*time.Second)
	defer cancel()
	type retryResult struct {
		data map[string]any
		err  error
	}
	var retry <-chan retryResult
	if server.cfg.NotificationsEnabled {
		if store, ok := server.service.store.(notificationStore); ok {
			// Retry delivery independently of booking/RTDB maintenance so an
			// unrelated dependency outage cannot starve email and push recovery.
			completed := make(chan retryResult, 1)
			retry = completed
			go func() {
				data, err := store.RetryOutbox(ctx)
				completed <- retryResult{data: data, err: err}
			}()
		}
	}
	result, err := server.service.RunMaintenance(ctx)
	if result == nil {
		result = map[string]any{}
	}
	if retry != nil {
		retried := <-retry
		result["notifications"] = retried.data
		err = errors.Join(err, retried.err)
	}
	if err != nil {
		writeServiceError(writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result})
}
