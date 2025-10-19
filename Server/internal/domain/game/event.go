package game

import (
	"time"

	"github.com/google/uuid"
)

// EventCategory はゲームイベントの大分類です。
type EventCategory string

// EventType はゲームイベントの詳細タイプです。
type EventType string

// 定義済みカテゴリの例。
const (
	EventCategoryAttack EventCategory = "attack"
	EventCategorySystem EventCategory = "system"
)

// Event は WebSocket を介してやり取りされるゲームイベントです。
type Event struct {
	ID        uuid.UUID
	SessionID uuid.UUID
	TriggerID uuid.UUID
	TargetID  uuid.UUID
	TriggerHP int
	TargetHP  int
	TriggerMP *int
	TargetMP  *int
	Category  EventCategory
	Type      EventType
	CreatedAt time.Time
}

// GameStateSnapshot はクライアントに返す状態のサマリです。
type GameStateSnapshot struct {
	Session Session
	Players map[uuid.UUID]PlayerState
}

// PlayerState はセッション内プレイヤーの最新状態です。
type PlayerState struct {
	Snapshot    PlayerSnapshot
	Participant Participant
}
