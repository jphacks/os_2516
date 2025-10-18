package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"server/internal/auth"
	"server/internal/config"
	"server/internal/game/hpmp"
	"server/internal/infrastructure/repository"
	"server/internal/supabase"
)

// NewRouter はアプリケーションの HTTP ルーティングを初期化します。
func NewRouter(supabaseClient supabase.Client, db *sql.DB, cfg *config.Config) http.Handler {

	// リポジトリを初期化
	var userRepo auth.UserRepository
	var sessionRepo auth.SessionRepository
	var playerRepo hpmp.PlayerRepository
	if db != nil {
		userRepo = repository.NewUserRepository(db)
		sessionRepo = repository.NewSessionRepository(db)
		playerRepo = repository.NewPlayerRepository(db)
	}

	// Apple認証サービスを初期化
	appleService := auth.NewAppleAuthService(
		cfg.Auth.AppleClientID,
		cfg.Auth.AppleTeamID,
		cfg.Auth.AppleKeyID,
	)

	// 認証ハンドラーを初期化
	authHandler := auth.NewAuthHandler(appleService, userRepo, sessionRepo, cfg.Auth.JWTSecret)

	// HP/MPハンドラーを初期化
	hpmpHandler := hpmp.NewHPMPHandler(playerRepo)

	// 認証ミドルウェアを初期化
	authMiddleware := auth.NewAuthMiddleware(cfg.Auth.JWTSecret, sessionRepo)

	// 基本ハンドラーを初期化
	handler := &Handler{supabase: supabaseClient}

	mux := http.NewServeMux()

	// ヘルスチェックエンドポイント
	mux.HandleFunc("/health", handler.health)
	mux.HandleFunc("/supabase/health", handler.supabaseHealth)

	// 認証エンドポイント
	mux.HandleFunc("/auth/apple/signin", authHandler.HandleAppleSignIn)
	mux.HandleFunc("/auth/refresh", authHandler.HandleRefresh)
	mux.HandleFunc("/auth/logout", authHandler.HandleLogout)

	// 保護されたエンドポイント（例）
	mux.Handle("/api/protected", authMiddleware.RequireAuth(http.HandlerFunc(handler.protected)))

	// HP/MP関連のエンドポイント
	mux.Handle("/api/hp", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleGetHP)))
	mux.Handle("/api/hp/update", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleUpdateHP)))
	mux.Handle("/api/mp", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleGetMP)))
	mux.Handle("/api/mp/update", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleUpdateMP)))

	return corsMiddleware(cfg.CORS.AllowedOrigins, loggingMiddleware(mux))
}

// Handler は HTTP ハンドラ群をまとめます。
type Handler struct {
	supabase supabase.Client
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) supabaseHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	if h.supabase == nil || !h.supabase.Ready() {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status":  "supabase_unconfigured",
			"message": "Set SUPABASE_DB_URL to enable this check.",
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()

	payload, err := h.supabase.Health(ctx)
	if err != nil {
		respondJSON(w, http.StatusBadGateway, map[string]string{
			"status":  "error",
			"message": err.Error(),
		})
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"status": payload.Status,
	})
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		duration := time.Since(start)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, duration.String())
	})
}

func methodNotAllowed(w http.ResponseWriter) {
	w.Header().Set("Allow", http.MethodGet)
	http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
}

func (h *Handler) protected(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	// 認証ミドルウェアからユーザーIDを取得
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "User ID not found in context", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"message": "This is a protected endpoint",
		"user_id": userID.String(),
	})
}

func corsMiddleware(allowedOrigins []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")

		// 許可されたオリジンをチェック
		allowed := false
		for _, allowedOrigin := range allowedOrigins {
			if allowedOrigin == "*" || allowedOrigin == origin {
				allowed = true
				break
			}
		}

		if allowed {
			w.Header().Set("Access-Control-Allow-Origin", origin)
		}

		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Credentials", "true")

		// プリフライトリクエストの処理
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func respondJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to encode json response: %v", err)
	}
}
