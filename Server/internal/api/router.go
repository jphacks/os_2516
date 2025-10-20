package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"sort"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	appbattlestage "server/internal/application/battlestage"
	"server/internal/auth"
	"server/internal/config"
	"server/internal/data"
	domainbattlestage "server/internal/domain/battlestage"
	"server/internal/domain/entities"
	"server/internal/domain/game"
	"server/internal/game/attack"
	"server/internal/game/hpmp"
	"server/internal/infrastructure/repository"
	"server/internal/session"
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
	var authSessionRepo auth.SessionRepository
	var playerRepo hpmp.PlayerRepository
	var battleSessionRepo session.Repository
	if db != nil {
		userRepo = repository.NewUserRepository(db)
		authSessionRepo = repository.NewSessionRepository(db)
		playerRepo = repository.NewPlayerRepository(db)
		battleSessionRepo = repository.NewGameSessionRepository(db)
	}

	// 認証ハンドラーを初期化
	authHandler := auth.NewAuthHandler(userRepo, playerRepo, authSessionRepo, cfg.Auth.JWTSecret)

	// HP/MPハンドラーを初期化
	hpmpHandler := hpmp.NewHPMPHandler(playerRepo)

	var sessionManager *session.Manager
	if battleSessionRepo != nil {
		resolver := attack.NewDefaultResolver()
		sessionManager = session.NewManager(battleSessionRepo, resolver)
	}

	var authMiddleware *auth.AuthMiddleware
	if authSessionRepo != nil {
		authMiddleware = auth.NewAuthMiddleware(cfg.Auth.JWTSecret, authSessionRepo)
	}

	// 基本ハンドラーを初期化
	handler := &Handler{
		supabase:       supabaseClient,
		magicTypesPath: "/home/nonroot/magic_types.json",
		sessionManager: sessionManager,
		sessionRepo:    battleSessionRepo,
		playerRepo:     playerRepo,
		config:         cfg,
	}
	if cfg != nil {
		handler.allowedOrigins = cfg.CORS.AllowedOrigins
	}
	if len(handler.allowedOrigins) == 0 {
		handler.allowedOrigins = []string{"*"}
	}
	handler.wsUpgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return originAllowed(r.Header.Get("Origin"), handler.allowedOrigins)
		},
	}

	if supabaseClient != nil && supabaseClient.Ready() {
		repo := repository.NewBattleStageSupabaseRepository(supabaseClient)
		handler.stageFinder = appbattlestage.NewNearbyFinder(repo, 1000.0)
	}

	mux := http.NewServeMux()

	// ヘルスチェックエンドポイント
	mux.HandleFunc("/health", handler.health)
	mux.HandleFunc("/supabase/health", handler.supabaseHealth)
	mux.HandleFunc("/ws", handler.websocket)
	mux.HandleFunc("/game", handler.listBattleStages)

	// 認証エンドポイント
	mux.HandleFunc("/auth/signup", authHandler.HandleSignUp)
	mux.HandleFunc("/auth/signin", authHandler.HandleSignIn)
	mux.HandleFunc("/auth/refresh", authHandler.HandleRefresh)
	if authMiddleware != nil {
		mux.Handle("/auth/logout", authMiddleware.RequireAuth(http.HandlerFunc(authHandler.HandleLogout)))
		mux.Handle("/protected", authMiddleware.RequireAuth(http.HandlerFunc(handler.protected)))
	} else {
		mux.HandleFunc("/auth/logout", authHandler.HandleLogout)
		mux.HandleFunc("/protected", methodNotAllowedHandler)
	}

	if authMiddleware != nil {
		// HP/MP関連のエンドポイント（認証必須）
		mux.Handle("/api/hp", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleGetHP)))
		mux.Handle("/api/hp/update", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleUpdateHP)))
		mux.Handle("/api/mp", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleGetMP)))
		mux.Handle("/api/mp/update", authMiddleware.RequireAuth(http.HandlerFunc(hpmpHandler.HandleUpdateMP)))
		mux.Handle("/api/game_sessions", authMiddleware.RequireAuth(http.HandlerFunc(handler.createGameSession)))
	} else {
		mux.HandleFunc("/api/hp", methodNotAllowedHandler)
		mux.HandleFunc("/api/hp/update", methodNotAllowedHandler)
		mux.HandleFunc("/api/mp", methodNotAllowedHandler)
		mux.HandleFunc("/api/mp/update", methodNotAllowedHandler)
		mux.HandleFunc("/api/game_sessions", methodNotAllowedHandler)
	}

	return corsMiddleware(cfg.CORS.AllowedOrigins, loggingMiddleware(mux))
}

// Handler は HTTP ハンドラ群をまとめます。
type Handler struct {
	supabase       supabase.Client
	stageFinder    BattleStageFinder
	sessionManager *session.Manager
	sessionRepo    session.Repository
	playerRepo     hpmp.PlayerRepository
	config         *config.Config
	allowedOrigins []string
	magicTypesPath string
	wsUpgrader     websocket.Upgrader
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

type createSessionRequest struct {
	StageID          string  `json:"stage_id"`
	OpponentPlayerID *string `json:"opponent_player_id,omitempty"`
}

type createSessionResponse struct {
	SessionID  string          `json:"session_id"`
	PlayerID   string          `json:"player_id"`
	OpponentID *string         `json:"opponent_id,omitempty"`
	StageID    string          `json:"stage_id"`
	State      *wsStatePayload `json:"state"`
}

func (h *Handler) createGameSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}

	if h.sessionRepo == nil || h.playerRepo == nil {
		http.Error(w, "session repository not configured", http.StatusServiceUnavailable)
		return
	}

	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "user context missing", http.StatusInternalServerError)
		return
	}

	var req createSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.StageID == "" {
		http.Error(w, "stage_id is required", http.StatusBadRequest)
		return
	}

	stageID, err := uuid.Parse(req.StageID)
	if err != nil {
		http.Error(w, "invalid stage_id", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	player, err := h.playerRepo.GetPlayerByUserID(ctx, userID)
	if err != nil {
		http.Error(w, "player not found", http.StatusNotFound)
		return
	}

	// 強制対戦相手が指定されていない場合、同一ステージの待機セッションを原子的に確保して参加する
	if (req.OpponentPlayerID == nil || *req.OpponentPlayerID == "") && h.sessionRepo != nil {
		newParticipant := session.NewParticipant{
			PlayerID:  player.ID,
			Role:      "challenger",
			InitialHP: player.HP,
			InitialMP: player.MP,
		}
		if sess, updatedParts, updatedSnaps, err := h.sessionRepo.ClaimAndAddParticipant(ctx, stageID, newParticipant, player.ID); err != nil {
			http.Error(w, fmt.Sprintf("failed to claim and join session: %v", err), http.StatusInternalServerError)
			return
		} else if sess != nil {
			// Successfully claimed and joined an existing session
			// reload session from repo to ensure latest
			sessReloaded, err := h.sessionRepo.GetSession(ctx, sess.ID)
			if err != nil {
				http.Error(w, fmt.Sprintf("failed to reload session: %v", err), http.StatusInternalServerError)
				return
			}
			if h.sessionManager != nil {
				h.sessionManager.RemoveSession(sessReloaded.ID)
			}

			playersState := make(map[uuid.UUID]game.PlayerState, len(updatedParts))
			for _, part := range updatedParts {
				snap, ok := updatedSnaps[part.PlayerID]
				if !ok {
					continue
				}
				playersState[part.PlayerID] = game.PlayerState{Participant: part, Snapshot: snap}
			}

			state := h.newStatePayload(game.GameStateSnapshot{Session: *sessReloaded, Players: playersState})

			var opponentIDPtr *string
			for _, part := range updatedParts {
				if part.PlayerID != player.ID {
					idStr := part.PlayerID.String()
					opponentIDPtr = &idStr
					break
				}
			}

			respondJSON(w, http.StatusCreated, createSessionResponse{
				SessionID:  sessReloaded.ID.String(),
				PlayerID:   player.ID.String(),
				OpponentID: opponentIDPtr,
				StageID:    sessReloaded.StageID.String(),
				State:      state,
			})
			return
		}
	}

	// 強制対戦相手が与えられている場合は即時マッチング、それ以外は待機セッションを新規作成
	var forcedOpponent *entities.Player
	if req.OpponentPlayerID != nil && *req.OpponentPlayerID != "" {
		opponentID, err := uuid.Parse(*req.OpponentPlayerID)
		if err != nil {
			http.Error(w, "invalid opponent_player_id", http.StatusBadRequest)
			return
		}
		if opponentID == player.ID {
			http.Error(w, "opponent must differ from player", http.StatusBadRequest)
			return
		}
		forcedOpponent, err = h.playerRepo.GetPlayerByID(ctx, opponentID)
		if err != nil {
			http.Error(w, "opponent player not found", http.StatusNotFound)
			return
		}
	}

	participants := []session.NewParticipant{
		{
			PlayerID:  player.ID,
			Role:      "host",
			InitialHP: player.HP,
			InitialMP: player.MP,
		},
	}

	if forcedOpponent != nil {
		participants = append(participants, session.NewParticipant{
			PlayerID:  forcedOpponent.ID,
			Role:      "guest",
			InitialHP: forcedOpponent.HP,
			InitialMP: forcedOpponent.MP,
		})
	}

	sess, metaParticipants, snapshots, err := h.sessionRepo.CreateSession(ctx, stageID, participants)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to create session: %v", err), http.StatusInternalServerError)
		return
	}

	if h.sessionManager != nil {
		h.sessionManager.RemoveSession(sess.ID)
	}

	playersState := make(map[uuid.UUID]game.PlayerState, len(metaParticipants))
	for _, part := range metaParticipants {
		snap, ok := snapshots[part.PlayerID]
		if !ok {
			continue
		}
		playersState[part.PlayerID] = game.PlayerState{Participant: part, Snapshot: snap}
	}

	state := h.newStatePayload(game.GameStateSnapshot{Session: *sess, Players: playersState})

	var opponentIDPtr *string
	if forcedOpponent != nil {
		idStr := forcedOpponent.ID.String()
		opponentIDPtr = &idStr
	}

	respondJSON(w, http.StatusCreated, createSessionResponse{
		SessionID:  sess.ID.String(),
		PlayerID:   player.ID.String(),
		OpponentID: opponentIDPtr,
		StageID:    sess.StageID.String(),
		State:      state,
	})
}

func (h *Handler) websocket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	if h.sessionManager == nil {
		http.Error(w, "session manager not configured", http.StatusServiceUnavailable)
		return
	}

	sessionParam := r.URL.Query().Get("session_id")
	playerParam := r.URL.Query().Get("player_id")
	if sessionParam == "" || playerParam == "" {
		http.Error(w, "session_id and player_id are required", http.StatusBadRequest)
		return
	}

	sessionID, err := uuid.Parse(sessionParam)
	if err != nil {
		http.Error(w, "invalid session_id", http.StatusBadRequest)
		return
	}
	playerID, err := uuid.Parse(playerParam)
	if err != nil {
		http.Error(w, "invalid player_id", http.StatusBadRequest)
		return
	}

	conn, err := h.wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		http.Error(w, "failed to upgrade connection", http.StatusBadRequest)
		return
	}

	battle, err := h.sessionManager.AttachConnection(r.Context(), sessionID, playerID, conn)
	if err != nil {
		h.writeWSError(conn, "attach_failed", err)
		_ = conn.Close()
		return
	}
	defer h.sessionManager.DetachConnection(sessionID, playerID)

	statePayload := h.newStatePayload(battle.Snapshot())
	var playerList []string
	for _, p := range statePayload.Players {
		playerList = append(playerList, fmt.Sprintf("%s(%s)", p.DisplayName, p.PlayerID))
	}
	log.Printf("ws:init session=%s to player=%s players=%v", sessionID.String(), playerID.String(), playerList)
	if err := conn.WriteJSON(wsServerMessage{Kind: "init", State: statePayload}); err != nil {
		log.Printf("websocket write error: %v", err)
		return
	}

	for {
		var incoming wsClientMessage
		if err := conn.ReadJSON(&incoming); err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("websocket read error: %v", err)
			}
			return
		}

		switch incoming.Kind {
		case "ping":
			if err := conn.WriteJSON(wsServerMessage{Kind: "pong"}); err != nil {
				log.Printf("websocket write error: %v", err)
				return
			}
		case "position_update":
			position, err := incoming.toPositionUpdate(sessionID, playerID)
			if err != nil {
				h.writeWSError(conn, "bad_request", err)
				continue
			}
			stored, err := h.sessionManager.UpdatePosition(sessionID, playerID, position)
			if err != nil {
				h.writeWSError(conn, "position_failed", err)
				continue
			}
			payload := newPositionPayload(stored)
			if err := conn.WriteJSON(wsServerMessage{Kind: "position_ack", Position: payload}); err != nil {
				log.Printf("websocket write error: %v", err)
				return
			}
			h.broadcast(sessionID, wsServerMessage{Kind: "position", Position: payload}, playerID)
		case "attack_triggered":
			request, err := incoming.toAttackRequest(sessionID, playerID)
			if err != nil {
				h.writeWSError(conn, "bad_request", err)
				continue
			}
			outcome, event, state, err := h.sessionManager.ResolveAttack(r.Context(), request)
			if err != nil {
				h.writeWSError(conn, "attack_failed", err)
				continue
			}
			statePayload := h.newStatePayload(state)
			var players []string
			for _, p := range statePayload.Players { players = append(players, p.DisplayName) }
			log.Printf("ws:event broadcast session=%s players=%v", sessionID.String(), players)
			response := wsServerMessage{
				Kind:         "event",
				Event:        newEventPayload(*event),
				State:        statePayload,
				AttackResult: newAttackResultPayload(request, outcome, event),
			}
			h.broadcast(sessionID, response, uuid.Nil)
		case "event":
			event, err := incoming.toDomainEvent(sessionID, playerID)
			if err != nil {
				h.writeWSError(conn, "bad_request", err)
				continue
			}
			event.CreatedAt = time.Now().UTC()

			state, err := h.sessionManager.ApplyEvent(r.Context(), event)
			if err != nil {
				h.writeWSError(conn, "apply_failed", err)
				continue
			}

			statePayload := h.newStatePayload(state)
			var players2 []string
			for _, p := range statePayload.Players { players2 = append(players2, p.DisplayName) }
			log.Printf("ws:event apply session=%s players=%v", sessionID.String(), players2)
			response := wsServerMessage{
				Kind:  "event",
				Event: newEventPayload(event),
				State: statePayload,
			}
			h.broadcast(sessionID, response, uuid.Nil)
		case "end":
			state, err := h.sessionManager.FinishSession(r.Context(), sessionID)
			if err != nil {
				h.writeWSError(conn, "finish_failed", err)
				continue
			}

			statePayload := h.newStatePayload(state)
			var players3 []string
			for _, p := range statePayload.Players { players3 = append(players3, p.DisplayName) }
			log.Printf("ws:end session=%s players=%v", sessionID.String(), players3)
			response := wsServerMessage{Kind: "end", State: statePayload}
			h.broadcast(sessionID, response, uuid.Nil)
			return
		default:
			h.writeWSError(conn, "unknown_kind", fmt.Errorf("unsupported kind %q", incoming.Kind))
		}
	}
}

func (h *Handler) broadcast(sessionID uuid.UUID, message wsServerMessage, exclude uuid.UUID) {
	if h.sessionManager == nil {
		return
	}

	conns := h.sessionManager.ActiveConnections(sessionID)
	for playerID, conn := range conns {
		if exclude != uuid.Nil && playerID == exclude {
			continue
		}
		if err := conn.WriteJSON(message); err != nil {
			log.Printf("websocket broadcast error: %v", err)
			h.sessionManager.DetachConnection(sessionID, playerID)
		}
	}
}

func (h *Handler) writeWSError(conn *websocket.Conn, code string, err error) {
	log.Printf("websocket error [%s]: %v", code, err)
	msg := wsServerMessage{
		Kind: "error",
		Error: &wsErrorPayload{
			Code:    code,
			Message: err.Error(),
		},
	}
	if writeErr := conn.WriteJSON(msg); writeErr != nil {
		log.Printf("websocket error send failed: %v", writeErr)
	}
}

type wsClientMessage struct {
	Kind      string          `json:"kind"`
	SessionID string          `json:"session_id,omitempty"`
	TriggerID string          `json:"trigger_id,omitempty"`
	TargetID  string          `json:"target_id,omitempty"`
	TriggerHP *int            `json:"trigger_hp,omitempty"`
	TargetHP  *int            `json:"target_hp,omitempty"`
	TriggerMP *int            `json:"trigger_mp,omitempty"`
	TargetMP  *int            `json:"target_mp,omitempty"`
	Category  string          `json:"category,omitempty"`
	EventType string          `json:"type,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
}

func (m wsClientMessage) toDomainEvent(sessionID uuid.UUID, defaultTrigger uuid.UUID) (game.Event, error) {
	event := game.Event{SessionID: sessionID}

	triggerID := defaultTrigger
	if m.TriggerID != "" {
		parsed, err := uuid.Parse(m.TriggerID)
		if err != nil {
			return game.Event{}, fmt.Errorf("invalid trigger_id: %w", err)
		}
		triggerID = parsed
	}
	event.TriggerID = triggerID

	if m.TargetID == "" {
		return game.Event{}, fmt.Errorf("target_id is required")
	}
	targetID, err := uuid.Parse(m.TargetID)
	if err != nil {
		return game.Event{}, fmt.Errorf("invalid target_id: %w", err)
	}
	event.TargetID = targetID

	if m.TriggerHP == nil {
		return game.Event{}, fmt.Errorf("trigger_hp is required")
	}
	if m.TargetHP == nil {
		return game.Event{}, fmt.Errorf("target_hp is required")
	}
	event.TriggerHP = *m.TriggerHP
	event.TargetHP = *m.TargetHP

	if m.TriggerMP != nil {
		value := *m.TriggerMP
		event.TriggerMP = &value
	}
	if m.TargetMP != nil {
		value := *m.TargetMP
		event.TargetMP = &value
	}

	if m.Category == "" {
		return game.Event{}, fmt.Errorf("category is required")
	}
	event.Category = game.EventCategory(m.Category)

	if m.EventType == "" {
		return game.Event{}, fmt.Errorf("type is required")
	}
	event.Type = game.EventType(m.EventType)

	return event, nil
}

func (m wsClientMessage) toPositionUpdate(sessionID, playerID uuid.UUID) (game.PlayerPosition, error) {
	if len(m.Payload) == 0 {
		return game.PlayerPosition{}, fmt.Errorf("payload is required for position_update")
	}
	var payload positionUpdatePayload
	if err := json.Unmarshal(m.Payload, &payload); err != nil {
		return game.PlayerPosition{}, fmt.Errorf("invalid position payload: %w", err)
	}
	return payload.toPlayerPosition(sessionID, playerID)
}

func (m wsClientMessage) toAttackRequest(sessionID, attackerID uuid.UUID) (game.AttackRequest, error) {
	if len(m.Payload) == 0 {
		return game.AttackRequest{}, fmt.Errorf("payload is required for attack_triggered")
	}
	var payload attackTriggerPayload
	if err := json.Unmarshal(m.Payload, &payload); err != nil {
		return game.AttackRequest{}, fmt.Errorf("invalid attack payload: %w", err)
	}
	position, err := payload.positionUpdatePayload.toPlayerPosition(sessionID, attackerID)
	if err != nil {
		return game.AttackRequest{}, err
	}
	targetIDStr := payload.TargetID
	if targetIDStr == "" {
		targetIDStr = m.TargetID
	}
	if targetIDStr == "" {
		return game.AttackRequest{}, fmt.Errorf("target_id is required for attack")
	}
	targetID, err := uuid.Parse(targetIDStr)
	if err != nil {
		return game.AttackRequest{}, fmt.Errorf("invalid target_id: %w", err)
	}
	chargeLevel := 0
	if payload.ChargeLevel != nil {
		chargeLevel = *payload.ChargeLevel
	}
	attackID := uuid.New()
	if payload.AttackID != "" {
		parsed, parseErr := uuid.Parse(payload.AttackID)
		if parseErr != nil {
			return game.AttackRequest{}, fmt.Errorf("invalid attackId: %w", parseErr)
		}
		attackID = parsed
	}
	return game.AttackRequest{
		SessionID:   sessionID,
		AttackerID:  attackerID,
		TargetID:    targetID,
		AttackID:    attackID,
		ChargeLevel: chargeLevel,
		Position:    position,
	}, nil
}

type positionUpdatePayload struct {
	Timestamp *time.Time       `json:"timestamp,omitempty"`
	Location  locationPayload  `json:"location"`
	Heading   *float64         `json:"heading,omitempty"`
	Accuracy  *accuracyPayload `json:"accuracy,omitempty"`
}

type attackTriggerPayload struct {
	positionUpdatePayload
	AttackID    string `json:"attackId,omitempty"`
	ChargeLevel *int   `json:"chargeLevel,omitempty"`
	TargetID    string `json:"targetId,omitempty"`
}

type locationPayload struct {
	Latitude  float64  `json:"lat"`
	Longitude float64  `json:"lon"`
	Altitude  *float64 `json:"alt,omitempty"`
}

type accuracyPayload struct {
	Horizontal float64  `json:"horizontal"`
	Vertical   *float64 `json:"vertical,omitempty"`
	Heading    *float64 `json:"heading,omitempty"`
}

func (p positionUpdatePayload) toPlayerPosition(sessionID, playerID uuid.UUID) (game.PlayerPosition, error) {
	if p.Heading == nil {
		return game.PlayerPosition{}, fmt.Errorf("heading is required")
	}
	recordedAt := time.Now().UTC()
	if p.Timestamp != nil && !p.Timestamp.IsZero() {
		recordedAt = p.Timestamp.UTC()
	}
	coordinate := game.Coordinate{
		Latitude:  p.Location.Latitude,
		Longitude: p.Location.Longitude,
	}
	if p.Location.Altitude != nil {
		alt := *p.Location.Altitude
		coordinate.Altitude = &alt
	}
	accuracy := game.PositionAccuracy{}
	if p.Accuracy != nil {
		accuracy.Horizontal = p.Accuracy.Horizontal
		if p.Accuracy.Vertical != nil {
			vert := *p.Accuracy.Vertical
			accuracy.Vertical = &vert
		}
		if p.Accuracy.Heading != nil {
			head := *p.Accuracy.Heading
			accuracy.Heading = &head
		}
	}
	return game.PlayerPosition{
		SessionID:  sessionID,
		PlayerID:   playerID,
		Coordinate: coordinate,
		Heading:    normalizeHeading(*p.Heading),
		Accuracy:   accuracy,
		RecordedAt: recordedAt,
	}, nil
}

func normalizeHeading(value float64) float64 {
	result := math.Mod(value, 360)
	if result < 0 {
		result += 360
	}
	return result
}

type wsServerMessage struct {
	Kind         string                 `json:"kind"`
	Event        *wsEventPayload        `json:"event,omitempty"`
	State        *wsStatePayload        `json:"state,omitempty"`
	Position     *wsPositionPayload     `json:"position,omitempty"`
	AttackResult *wsAttackResultPayload `json:"attack_result,omitempty"`
	Error        *wsErrorPayload        `json:"error,omitempty"`
	Info         string                 `json:"info,omitempty"`
}

type wsErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type wsEventPayload struct {
	SessionID  string    `json:"session_id"`
	TriggerID  string    `json:"trigger_id"`
	TargetID   string    `json:"target_id"`
	TriggerHP  int       `json:"trigger_hp"`
	TargetHP   int       `json:"target_hp"`
	TriggerMP  *int      `json:"trigger_mp,omitempty"`
	TargetMP   *int      `json:"target_mp,omitempty"`
	Category   string    `json:"category"`
	Type       string    `json:"type"`
	OccurredAt time.Time `json:"occurred_at"`
}

type wsPositionPayload struct {
	PlayerID  string           `json:"player_id"`
	Timestamp time.Time        `json:"timestamp"`
	Location  locationPayload  `json:"location"`
	Heading   float64          `json:"heading"`
	Accuracy  *accuracyPayload `json:"accuracy,omitempty"`
}

type wsAttackResultPayload struct {
	AttackID    string    `json:"attack_id"`
	AttackerID  string    `json:"attacker_id"`
	TargetID    string    `json:"target_id"`
	ChargeLevel int       `json:"charge_level"`
	Hit         bool      `json:"hit"`
	Damage      int       `json:"damage"`
	TriggerHP   int       `json:"trigger_hp"`
	TargetHP    int       `json:"target_hp"`
	TriggerMP   *int      `json:"trigger_mp,omitempty"`
	TargetMP    *int      `json:"target_mp,omitempty"`
	OccurredAt  time.Time `json:"occurred_at"`
}

type wsStatePayload struct {
	SessionID string          `json:"session_id"`
	StageID   string          `json:"stage_id"`
	Status    string          `json:"status"`
	Mode      string          `json:"mode"`
	StartedAt *time.Time      `json:"started_at,omitempty"`
	EndedAt   *time.Time      `json:"ended_at,omitempty"`
	Players   []wsPlayerState `json:"players"`
}

type wsPlayerState struct {
	PlayerID       string  `json:"player_id"`
	Role           string  `json:"role"`
	DisplayName    string  `json:"display_name,omitempty"`
	HP             int     `json:"hp"`
	MP             int     `json:"mp"`
	Stance         *string `json:"stance,omitempty"`
	LastPositionID *string `json:"last_position_id,omitempty"`
	Position       *wsPositionPayload `json:"position,omitempty"`
}

func newEventPayload(event game.Event) *wsEventPayload {
	payload := &wsEventPayload{
		SessionID:  event.SessionID.String(),
		TriggerID:  event.TriggerID.String(),
		TargetID:   event.TargetID.String(),
		TriggerHP:  event.TriggerHP,
		TargetHP:   event.TargetHP,
		Category:   string(event.Category),
		Type:       string(event.Type),
		OccurredAt: event.CreatedAt,
	}
	if event.TriggerMP != nil {
		value := *event.TriggerMP
		payload.TriggerMP = &value
	}
	if event.TargetMP != nil {
		value := *event.TargetMP
		payload.TargetMP = &value
	}
	return payload
}

func newPositionPayload(position game.PlayerPosition) *wsPositionPayload {
	payload := &wsPositionPayload{
		PlayerID:  position.PlayerID.String(),
		Timestamp: position.RecordedAt,
		Location: locationPayload{
			Latitude:  position.Coordinate.Latitude,
			Longitude: position.Coordinate.Longitude,
		},
		Heading: normalizeHeading(position.Heading),
	}
	if position.Coordinate.Altitude != nil {
		alt := *position.Coordinate.Altitude
		payload.Location.Altitude = &alt
	}
	if position.Accuracy.Horizontal != 0 || position.Accuracy.Vertical != nil || position.Accuracy.Heading != nil {
		acc := accuracyPayload{Horizontal: position.Accuracy.Horizontal}
		if position.Accuracy.Vertical != nil {
			vert := *position.Accuracy.Vertical
			acc.Vertical = &vert
		}
		if position.Accuracy.Heading != nil {
			head := *position.Accuracy.Heading
			acc.Heading = &head
		}
		payload.Accuracy = &acc
	}
	return payload
}

func newAttackResultPayload(request game.AttackRequest, outcome game.AttackOutcome, event *game.Event) *wsAttackResultPayload {
	payload := &wsAttackResultPayload{
		AttackID:    request.AttackID.String(),
		AttackerID:  request.AttackerID.String(),
		TargetID:    request.TargetID.String(),
		ChargeLevel: request.ChargeLevel,
		Hit:         outcome.Hit,
		Damage:      outcome.Damage,
		OccurredAt:  request.Position.RecordedAt,
	}
	if payload.OccurredAt.IsZero() {
		payload.OccurredAt = time.Now().UTC()
	}
	if event != nil {
		payload.TriggerHP = event.TriggerHP
		payload.TargetHP = event.TargetHP
		payload.OccurredAt = event.CreatedAt
		if event.TriggerMP != nil {
			value := *event.TriggerMP
			payload.TriggerMP = &value
		}
		if event.TargetMP != nil {
			value := *event.TargetMP
			payload.TargetMP = &value
		}
	}
	return payload
}

func (h *Handler) newStatePayload(snapshot game.GameStateSnapshot) *wsStatePayload {
	players := make([]wsPlayerState, 0, len(snapshot.Players))
	for id, state := range snapshot.Players {
		player := wsPlayerState{
			PlayerID: id.String(),
			Role:     state.Participant.Role,
			HP:       state.Snapshot.HP,
			MP:       state.Snapshot.MP,
		}
		// try to resolve display name from player repository if available
		if h.playerRepo != nil {
			if p, err := h.playerRepo.GetPlayerByID(context.Background(), id); err == nil && p != nil {
				player.DisplayName = p.DisplayName
			}
		}
		if state.Snapshot.Stance != nil {
			stance := *state.Snapshot.Stance
			player.Stance = &stance
		}
		if state.Snapshot.LastPositionID != nil {
			value := state.Snapshot.LastPositionID.String()
			player.LastPositionID = &value
		}
		if state.Position != nil {
			// include latest known position snapshot for the player
			pos := newPositionPayload(*state.Position)
			player.Position = pos
		}
		players = append(players, player)
	}

	sort.Slice(players, func(i, j int) bool { return players[i].PlayerID < players[j].PlayerID })

	return &wsStatePayload{
		SessionID: snapshot.Session.ID.String(),
		StageID:   snapshot.Session.StageID.String(),
		Status:    string(snapshot.Session.Status),
		Mode:      snapshot.Session.Mode,
		StartedAt: snapshot.Session.StartedAt,
		EndedAt:   snapshot.Session.EndedAt,
		Players:   players,
	}
}

func originAllowed(origin string, allowedOrigins []string) bool {
	if len(allowedOrigins) == 0 {
		return false
	}

	for _, allowed := range allowedOrigins {
		if allowed == "*" {
			return true
		}

		if origin != "" && allowed == origin {
			return true
		}
	}

	return false
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

func methodNotAllowedHandler(w http.ResponseWriter, r *http.Request) {
	methodNotAllowed(w)
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

func (h *Handler) listMagicTypes(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	list, err := data.LoadMagicTypes(h.magicTypesPath)
	if err != nil {
		log.Printf("failed to load magic types: %v", err)
		http.Error(w, "failed to load magic types", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, list)
}

func corsMiddleware(allowedOrigins []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")

		// 許可されたオリジンをチェック
		if originAllowed(origin, allowedOrigins) {
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
