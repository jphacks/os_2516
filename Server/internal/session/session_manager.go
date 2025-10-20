package session

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"server/internal/domain/game"
	"server/internal/game/attack"
)

// ErrSessionNotFound は要求されたセッションが存在しない場合に返されます。
var ErrSessionNotFound = errors.New("battle session not found")

// ErrPlayerNotInSession はプレイヤーがセッションに所属していない場合に返されます。
var ErrPlayerNotInSession = errors.New("player not part of session")

const (
	baseMPCost   = 10
	chargeMPCost = 5
)

// Repository はセッションデータを取得・更新するための抽象化です。
type Repository interface {
	GetSession(ctx context.Context, sessionID uuid.UUID) (*game.Session, error)
	ListParticipants(ctx context.Context, sessionID uuid.UUID) ([]game.Participant, error)
	ListPlayerSnapshots(ctx context.Context, sessionID uuid.UUID) (map[uuid.UUID]game.PlayerSnapshot, error)
	SaveEventWithSnapshots(ctx context.Context, event game.Event, snapshots map[uuid.UUID]game.PlayerSnapshot) error
	UpdateSessionStatus(ctx context.Context, sessionID uuid.UUID, status game.SessionStatus, endedAt *time.Time) error
	CreateSession(ctx context.Context, stageID uuid.UUID, participants []NewParticipant) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error)
	FindJoinableSession(ctx context.Context, stageID uuid.UUID, excludePlayer uuid.UUID) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error)
	AddParticipant(ctx context.Context, sessionID uuid.UUID, participant NewParticipant, activate bool) ([]game.Participant, map[uuid.UUID]game.PlayerSnapshot, error)
		// ClaimAndAddParticipant atomically finds a joinable session and adds the participant in a single transaction.
		// Returns nil,nil,nil,nil if no joinable session exists.
		ClaimAndAddParticipant(ctx context.Context, stageID uuid.UUID, participant NewParticipant, excludePlayer uuid.UUID) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error)
}

// NewParticipant は新規セッション作成時の参加者情報です。
type NewParticipant struct {
	PlayerID  uuid.UUID
	Role      string
	InitialHP int
	InitialMP int
}

// SessionPlayer はセッションに参加するプレイヤー状態です。
type SessionPlayer struct {
	Participant  game.Participant
	Snapshot     game.PlayerSnapshot
	LastPosition *game.PlayerPosition
}

// BattleSession はゲームセッションのインメモリ表現です。
type BattleSession struct {
	Session     game.Session
	Players     map[uuid.UUID]*SessionPlayer
	Connections map[uuid.UUID]*websocket.Conn
	mu          sync.RWMutex
}

// Snapshot は現在のゲーム状態を取得します。
func (bs *BattleSession) Snapshot() game.GameStateSnapshot {
	bs.mu.RLock()
	defer bs.mu.RUnlock()

	players := make(map[uuid.UUID]game.PlayerState, len(bs.Players))
	for id, player := range bs.Players {
		var position *game.PlayerPosition
		if player.LastPosition != nil {
			posCopy := player.LastPosition.Clone()
			position = &posCopy
		}
		players[id] = game.PlayerState{
			Snapshot:    player.Snapshot.Clone(),
			Participant: player.Participant,
			Position:    position,
		}
	}

	return game.GameStateSnapshot{
		Session: bs.Session,
		Players: players,
	}
}

// Manager はゲームセッションのライフサイクルを統括します。
type Manager struct {
	repo           Repository
	sessions       map[uuid.UUID]*BattleSession
	mu             sync.RWMutex
	attackResolver *attack.Resolver
}

// NewManager は新しい Manager を生成します。
func NewManager(repo Repository, resolver *attack.Resolver) *Manager {
	return &Manager{
		repo:           repo,
		sessions:       make(map[uuid.UUID]*BattleSession),
		attackResolver: resolver,
	}
}

// AttachConnection はプレイヤーの WebSocket 接続をセッションに紐付けます。
func (m *Manager) AttachConnection(ctx context.Context, sessionID, playerID uuid.UUID, conn *websocket.Conn) (*BattleSession, error) {
	bs, err := m.getOrLoadSession(ctx, sessionID)
	if err != nil {
		return nil, err
	}

	bs.mu.Lock()
	defer bs.mu.Unlock()

	player, ok := bs.Players[playerID]
	if !ok {
		return nil, ErrPlayerNotInSession
	}

	if existing := bs.Connections[playerID]; existing != nil && existing != conn {
		_ = existing.Close()
	}
	bs.Connections[playerID] = conn

	// 自分のスナップショットを最新化（DB未反映時の再接続対応）
	player.Snapshot.UpdatedAt = time.Now()

	return bs, nil
}

// SetAttackResolver は攻撃判定ロジックを差し替えます。
func (m *Manager) SetAttackResolver(resolver *attack.Resolver) {
	m.attackResolver = resolver
}

// UpdatePosition はプレイヤーの最新位置を更新します。
func (m *Manager) UpdatePosition(sessionID, playerID uuid.UUID, position game.PlayerPosition) (game.PlayerPosition, error) {
	bs, err := m.getExistingSession(sessionID)
	if err != nil {
		return game.PlayerPosition{}, err
	}

	if position.RecordedAt.IsZero() {
		position.RecordedAt = time.Now()
	}
	position.SessionID = sessionID
	position.PlayerID = playerID

	bs.mu.Lock()
	defer bs.mu.Unlock()

	player, ok := bs.Players[playerID]
	if !ok {
		return game.PlayerPosition{}, ErrPlayerNotInSession
	}

	copy := position.Clone()
	player.LastPosition = &copy

	return copy, nil
}

// DetachConnection はプレイヤー接続を解除します。
func (m *Manager) DetachConnection(sessionID, playerID uuid.UUID) {
	m.mu.RLock()
	bs := m.sessions[sessionID]
	m.mu.RUnlock()
	if bs == nil {
		return
	}

	bs.mu.Lock()
	if conn := bs.Connections[playerID]; conn != nil {
		_ = conn.Close()
	}
	delete(bs.Connections, playerID)
	bs.mu.Unlock()
}

// RemoveSession はインメモリのセッションを破棄します。
func (m *Manager) RemoveSession(sessionID uuid.UUID) {
	m.mu.Lock()
	bs := m.sessions[sessionID]
	delete(m.sessions, sessionID)
	m.mu.Unlock()

	if bs == nil {
		return
	}

	bs.mu.Lock()
	defer bs.mu.Unlock()
	for id, conn := range bs.Connections {
		if conn != nil {
			_ = conn.Close()
		}
		delete(bs.Connections, id)
	}
}

// ResolveAttack は攻撃リクエストを評価し、結果に応じたイベントを生成します。
func (m *Manager) ResolveAttack(ctx context.Context, request game.AttackRequest) (game.AttackOutcome, *game.Event, game.GameStateSnapshot, error) {
	if m.attackResolver == nil {
		return game.AttackOutcome{Request: request}, nil, game.GameStateSnapshot{}, fmt.Errorf("attack resolver not configured")
	}

	if request.AttackID == uuid.Nil {
		request.AttackID = uuid.New()
	}
	position := request.Position.Clone()
	if position.RecordedAt.IsZero() {
		position.RecordedAt = time.Now()
	}
	position.SessionID = request.SessionID
	position.PlayerID = request.AttackerID
	request.Position = position

	bs, err := m.getExistingSession(request.SessionID)
	if err != nil {
		return game.AttackOutcome{Request: request}, nil, game.GameStateSnapshot{}, err
	}

	bs.mu.Lock()
	attacker, ok := bs.Players[request.AttackerID]
	if !ok {
		bs.mu.Unlock()
		return game.AttackOutcome{Request: request}, nil, game.GameStateSnapshot{}, ErrPlayerNotInSession
	}
	target, ok := bs.Players[request.TargetID]
	if !ok {
		bs.mu.Unlock()
		return game.AttackOutcome{Request: request}, nil, game.GameStateSnapshot{}, ErrPlayerNotInSession
	}

	attackerPos := position.Clone()
	attacker.LastPosition = &attackerPos

	attackerSnapshot := attacker.Snapshot.Clone()
	targetSnapshot := target.Snapshot.Clone()

	var targetPosition *game.PlayerPosition
	if target.LastPosition != nil {
		copy := target.LastPosition.Clone()
		targetPosition = &copy
	}
	bs.mu.Unlock()

	outcome, err := m.attackResolver.Resolve(request, position, targetPosition)
	if err != nil {
		return outcome, nil, game.GameStateSnapshot{}, err
	}

	event := game.Event{
		ID:        uuid.New(),
		SessionID: request.SessionID,
		TriggerID: request.AttackerID,
		TargetID:  request.TargetID,
		TriggerHP: attackerSnapshot.HP,
		TargetHP:  targetSnapshot.HP,
		Category:  game.EventCategoryAttack,
		Type:      game.EventTypeFire,
		CreatedAt: position.RecordedAt,
	}

	mpCost := computeMPCost(request.ChargeLevel)
	if mpCost > 0 {
		triggerMP := attackerSnapshot.MP - mpCost
		if triggerMP < 0 {
			triggerMP = 0
		}
		if triggerMP != attackerSnapshot.MP {
			event.TriggerMP = &triggerMP
		}
	}

	if outcome.Hit {
		newHP := targetSnapshot.HP - outcome.Damage
		if newHP < 0 {
			newHP = 0
		}
		event.TargetHP = newHP
	}

	state, err := m.ApplyEvent(ctx, event)
	if err != nil {
		return outcome, nil, game.GameStateSnapshot{}, err
	}

	return outcome, &event, state, nil
}

// ApplyEvent はゲームイベントを適用しDBへ永続化します。
func (m *Manager) ApplyEvent(ctx context.Context, event game.Event) (game.GameStateSnapshot, error) {
	bs, err := m.getExistingSession(event.SessionID)
	if err != nil {
		return game.GameStateSnapshot{}, err
	}

	now := time.Now()
	if event.CreatedAt.IsZero() {
		event.CreatedAt = now
	}

	bs.mu.Lock()
	trigger, ok := bs.Players[event.TriggerID]
	if !ok {
		bs.mu.Unlock()
		return game.GameStateSnapshot{}, ErrPlayerNotInSession
	}

	target, ok := bs.Players[event.TargetID]
	if !ok {
		bs.mu.Unlock()
		return game.GameStateSnapshot{}, ErrPlayerNotInSession
	}

	// 既存状態のバックアップ
	triggerBefore := trigger.Snapshot.Clone()
	targetBefore := triggerBefore
	if event.TargetID != event.TriggerID {
		targetBefore = target.Snapshot.Clone()
	}

	// 状態更新
	trigger.Snapshot.HP = event.TriggerHP
	trigger.Snapshot.UpdatedAt = event.CreatedAt
	if event.TriggerMP != nil {
		trigger.Snapshot.MP = *event.TriggerMP
	}

	if event.TargetID == event.TriggerID {
		if event.TargetMP != nil {
			trigger.Snapshot.MP = *event.TargetMP
		}
	} else {
		target.Snapshot.HP = event.TargetHP
		target.Snapshot.UpdatedAt = event.CreatedAt
		if event.TargetMP != nil {
			target.Snapshot.MP = *event.TargetMP
		}
	}

	updatedSnapshots := map[uuid.UUID]game.PlayerSnapshot{
		event.TriggerID: trigger.Snapshot.Clone(),
	}
	if event.TargetID != event.TriggerID {
		updatedSnapshots[event.TargetID] = target.Snapshot.Clone()
	} else {
		updatedSnapshots[event.TriggerID] = trigger.Snapshot.Clone()
	}
	bs.mu.Unlock()

	if err := m.repo.SaveEventWithSnapshots(ctx, event, updatedSnapshots); err != nil {
		bs.mu.Lock()
		trigger.Snapshot = triggerBefore
		if event.TargetID == event.TriggerID {
			trigger.Snapshot = targetBefore
		} else {
			target.Snapshot = targetBefore
		}
		bs.mu.Unlock()
		return game.GameStateSnapshot{}, fmt.Errorf("failed to persist event: %w", err)
	}

	return bs.Snapshot(), nil
}

// FinishSession はゲーム終了をマークし、DBとインメモリ状態を更新します。
func (m *Manager) FinishSession(ctx context.Context, sessionID uuid.UUID) (game.GameStateSnapshot, error) {
	bs, err := m.getExistingSession(sessionID)
	if err != nil {
		return game.GameStateSnapshot{}, err
	}

	finishedAt := time.Now()
	if err := m.repo.UpdateSessionStatus(ctx, sessionID, game.SessionStatusFinished, &finishedAt); err != nil {
		return game.GameStateSnapshot{}, fmt.Errorf("failed to update session status: %w", err)
	}

	bs.mu.Lock()
	bs.Session.Status = game.SessionStatusFinished
	bs.Session.EndedAt = &finishedAt
	bs.mu.Unlock()

	return bs.Snapshot(), nil
}

// ActiveConnections は現在アタッチされている接続を返します。
func (m *Manager) ActiveConnections(sessionID uuid.UUID) map[uuid.UUID]*websocket.Conn {
	m.mu.RLock()
	bs := m.sessions[sessionID]
	m.mu.RUnlock()
	if bs == nil {
		return nil
	}

	bs.mu.RLock()
	defer bs.mu.RUnlock()
	conns := make(map[uuid.UUID]*websocket.Conn, len(bs.Connections))
	for id, conn := range bs.Connections {
		if conn != nil {
			conns[id] = conn
		}
	}
	return conns
}

func (m *Manager) getExistingSession(sessionID uuid.UUID) (*BattleSession, error) {
	m.mu.RLock()
	bs := m.sessions[sessionID]
	m.mu.RUnlock()
	if bs == nil {
		return nil, ErrSessionNotFound
	}
	return bs, nil
}

func (m *Manager) getOrLoadSession(ctx context.Context, sessionID uuid.UUID) (*BattleSession, error) {
	m.mu.RLock()
	if bs, ok := m.sessions[sessionID]; ok {
		m.mu.RUnlock()
		return bs, nil
	}
	m.mu.RUnlock()

	bs, err := m.loadBattleSession(ctx, sessionID)
	if err != nil {
		return nil, err
	}

	m.mu.Lock()
	m.sessions[sessionID] = bs
	m.mu.Unlock()
	return bs, nil
}

func (m *Manager) loadBattleSession(ctx context.Context, sessionID uuid.UUID) (*BattleSession, error) {
	sess, err := m.repo.GetSession(ctx, sessionID)
	if err != nil {
		if errors.Is(err, ErrSessionNotFound) {
			return nil, err
		}
		return nil, fmt.Errorf("failed to load session: %w", err)
	}
	if sess == nil {
		return nil, ErrSessionNotFound
	}

	participants, err := m.repo.ListParticipants(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to list participants: %w", err)
	}

	snapshots, err := m.repo.ListPlayerSnapshots(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to list player snapshots: %w", err)
	}

	players := make(map[uuid.UUID]*SessionPlayer, len(participants))
	for _, part := range participants {
		snap, ok := snapshots[part.PlayerID]
		if !ok {
			snap = game.PlayerSnapshot{
				SessionID: sessionID,
				PlayerID:  part.PlayerID,
				HP:        part.InitialHP,
				MP:        part.InitialMP,
				UpdatedAt: time.Now(),
			}
		}
		players[part.PlayerID] = &SessionPlayer{
			Participant: part,
			Snapshot:    snap,
		}
	}

	return &BattleSession{
		Session:     *sess,
		Players:     players,
		Connections: make(map[uuid.UUID]*websocket.Conn),
	}, nil
}

func computeMPCost(chargeLevel int) int {
	if chargeLevel < 0 {
		chargeLevel = 0
	}
	return baseMPCost + (chargeLevel * chargeMPCost)
}
