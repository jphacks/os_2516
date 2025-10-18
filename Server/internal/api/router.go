package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	appbattlestage "server/internal/application/battlestage"
	domainbattlestage "server/internal/domain/battlestage"
	"server/internal/auth"
	"server/internal/config"
	"server/internal/game/hpmp"
	"server/internal/infrastructure/repository"
	"server/internal/supabase"
)

// BattleStageFinder はステージ検索ユースケースのインターフェースです。
type BattleStageFinder interface {
	Execute(ctx context.Context, location domainbattlestage.Location) ([]domainbattlestage.StageWithDistance, error)
	SearchRadius() float64
}

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
	authHandler := auth.NewAuthHandler(appleService, userRepo, playerRepo, sessionRepo, cfg.Auth.JWTSecret)

	// HP/MPハンドラーを初期化
	hpmpHandler := hpmp.NewHPMPHandler(playerRepo)

	// 認証ミドルウェアを初期化
	authMiddleware := auth.NewAuthMiddleware(cfg.Auth.JWTSecret, sessionRepo)

	// 基本ハンドラーを初期化
	handler := &Handler{supabase: supabaseClient}

	if supabaseClient != nil && supabaseClient.Ready() {
		repo := repository.NewBattleStageSupabaseRepository(supabaseClient)
		handler.stageFinder = appbattlestage.NewNearbyFinder(repo, 1000.0)
	}

	mux := http.NewServeMux()

	// ヘルスチェックエンドポイント
	mux.HandleFunc("/health", handler.health)
	mux.HandleFunc("/supabase/health", handler.supabaseHealth)
	mux.HandleFunc("/game", handler.listBattleStages)

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
	supabase    supabase.Client
	stageFinder BattleStageFinder
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

func (h *Handler) listBattleStages(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	if h.stageFinder == nil {
		respondJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status":  "supabase_unconfigured",
			"message": "database client not ready",
		})
		return
	}

	query := r.URL.Query()
	latParam := query.Get("lat")
	lngParam := query.Get("lng")

	if latParam == "" || lngParam == "" {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"status":  "invalid_request",
			"message": "query parameters 'lat' and 'lng' are required",
		})
		return
	}

	latitude, err := strconv.ParseFloat(latParam, 64)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"status":  "invalid_latitude",
			"message": "unable to parse 'lat' as float",
		})
		return
	}

	longitude, err := strconv.ParseFloat(lngParam, 64)
	if err != nil {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"status":  "invalid_longitude",
			"message": "unable to parse 'lng' as float",
		})
		return
	}

	if latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 {
		respondJSON(w, http.StatusBadRequest, map[string]string{
			"status":  "invalid_coordinates",
			"message": "latitude must be between -90 and 90, longitude between -180 and 180",
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	results, err := h.stageFinder.Execute(ctx, domainbattlestage.Location{
		Latitude:  latitude,
		Longitude: longitude,
	})
	if err != nil {
		respondJSON(w, http.StatusBadGateway, map[string]string{
			"status":  "supabase_query_failed",
			"message": err.Error(),
		})
		return
	}

	payload := make([]battleStageResponse, 0, len(results))
	for _, result := range results {
		payload = append(payload, toBattleStageResponse(result))
	}

	respondJSON(w, http.StatusOK, map[string]any{
		"battleStages": payload,
		"radiusMeters": h.stageFinder.SearchRadius(),
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

type battleStageResponse struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	Latitude       float64  `json:"latitude"`
	Longitude      float64  `json:"longitude"`
	RadiusMeters   *float64 `json:"radiusMeters,omitempty"`
	Description    *string  `json:"description,omitempty"`
	DistanceMeters float64  `json:"distanceMeters"`
}

func toBattleStageResponse(stage domainbattlestage.StageWithDistance) battleStageResponse {
	return battleStageResponse{
		ID:             stage.Stage.ID,
		Name:           stage.Stage.Name,
		Latitude:       stage.Stage.Location.Latitude,
		Longitude:      stage.Stage.Location.Longitude,
		RadiusMeters:   stage.Stage.RadiusMeters,
		Description:    stage.Stage.Description,
		DistanceMeters: stage.DistanceMeters,
	}
}
