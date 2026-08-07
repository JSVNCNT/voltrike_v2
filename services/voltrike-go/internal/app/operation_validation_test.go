package app

import (
	"context"
	"errors"
	"testing"
)

type operationValidationStore struct{ called bool }

func (store *operationValidationStore) LoadPolicy(context.Context) (Policy, error) {
	return Policy{}, nil
}
func (store *operationValidationStore) ReadDispatchCell(context.Context, string) (map[string]DispatchPresence, error) {
	return nil, nil
}
func (store *operationValidationStore) ExecuteOperation(context.Context, Principal, OperationCommand) (map[string]any, error) {
	store.called = true
	return map[string]any{"ok": true}, nil
}

func TestExecuteOperationRejectsUnsafeCommandIDBeforeStore(t *testing.T) {
	store := &operationValidationStore{}
	service := &Service{store: store}
	for _, commandID := range []string{"", "unsafe/path", "bad#key"} {
		_, err := service.ExecuteOperation(context.Background(), Principal{UID: "user-1"}, OperationCommand{
			Name: "example", CommandID: commandID,
		})
		if !errors.Is(err, ErrInvalidArgument) {
			t.Fatalf("commandId %q returned %v", commandID, err)
		}
	}
	if store.called {
		t.Fatal("invalid command reached operation store")
	}
}
