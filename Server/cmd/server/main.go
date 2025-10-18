package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"server/internal/api"
	"server/internal/config"
	"server/internal/supabase"

	_ "github.com/lib/pq" // PostgreSQL driver
)

func main() {
	if err := config.LoadEnvFiles(".env", "../.env"); err != nil {
		log.Printf("failed to load env file: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 設定を読み込み
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// データベース接続を初期化
	var db *sql.DB
	if cfg.Database.URL != "" {
		db, err = sql.Open("postgres", cfg.Database.URL)
		if err != nil {
			log.Fatalf("Failed to connect to database: %v", err)
		}
		defer db.Close()

		// データベース接続をテスト
		if err := db.Ping(); err != nil {
			log.Fatalf("Failed to ping database: %v", err)
		}
		log.Println("Database connection established")
	}

	// Supabaseクライアントを初期化
	startupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	supabaseClient, err := supabase.NewClientFromEnv(startupCtx)
	cancel()
	if err != nil {
		log.Printf("Supabase Postgres client disabled: %v", err)
	}
	defer supabaseClient.Close()

	// ルーターを初期化（データベース接続を渡す）
	router := api.NewRouter(supabaseClient, db, cfg)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:    ":" + port,
		Handler: router,
	}

	go func() {
		log.Printf("HTTP server listening on %s", server.Addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-ctx.Done()
	log.Printf("shutdown signal received")

	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelShutdown()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}

	log.Printf("server stopped")
}
