package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"

	"server/internal/supabase"
)

// NewRouter はアプリケーションの HTTP ルーティングを初期化します。
func NewRouter(supabaseClient supabase.Client) http.Handler {
	handler := &Handler{supabase: supabaseClient}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", handler.health)
	mux.HandleFunc("/supabase/health", handler.supabaseHealth)
	mux.HandleFunc("/ws", handler.websocket)

	return loggingMiddleware(mux)
}

// Handler は HTTP ハンドラ群をまとめます。
type Handler struct {
	supabase supabase.Client
}

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
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

func (h *Handler) websocket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		http.Error(w, "failed to upgrade connection", http.StatusBadRequest)
		return
	}
	defer conn.Close()

	for {
		msgType, payload, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("websocket read error: %v", err)
			}
			return
		}

		if err := conn.WriteMessage(msgType, payload); err != nil {
			log.Printf("websocket write error: %v", err)
			return
		}
	}
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

func respondJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to encode json response: %v", err)
	}
}
