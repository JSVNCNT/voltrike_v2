package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/voltrike/voltrike-go/internal/firebase"
)

func main() {
	project := flag.String("project", "voltrike-v2", "Original Firebase project for the fixed synthetic dataset")
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	store, closeStore, err := firebase.OpenDemoActivation(ctx, *project)
	if err != nil {
		slog.Error("open demo activation", "error", err)
		os.Exit(1)
	}
	defer closeStore()
	summary, err := store.ActivateDemo(ctx)
	if err != nil {
		slog.Error("demo activation failed", "error", err)
		os.Exit(1)
	}
	encoded, err := json.Marshal(summary)
	if err != nil {
		slog.Error("encode demo activation result", "error", err)
		os.Exit(1)
	}
	fmt.Println(string(encoded))
}
