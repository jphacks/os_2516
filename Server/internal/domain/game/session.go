package game

import (
	"time"

	"github.com/google/uuid"
)

// SessionStatus はゲームセッションの状態を表します。
type SessionStatus string

const (
	SessionStatusPreparing SessionStatus = "preparing"
	SessionStatusActive    SessionStatus = "active"
	SessionStatusFinished  SessionStatus = "finished"
)

// Session はゲームセッションのメタ情報です。
type Session struct {
	ID        uuid.UUID
	StageID   uuid.UUID
	Mode      string
	Status    SessionStatus
	StartedAt *time.Time
	EndedAt   *time.Time
}

// Participant はセッションに参加するプレイヤー情報です。
type Participant struct {
	PlayerID  uuid.UUID
	Role      string
	InitialHP int
	InitialMP int
}

// PlayerSnapshot は現在のプレイヤー状態を表します。
type PlayerSnapshot struct {
	SessionID      uuid.UUID
	PlayerID       uuid.UUID
	HP             int
	MP             int
	Stance         *string
	LastPositionID *uuid.UUID
	UpdatedAt      time.Time
}

// Clone はスナップショットのディープコピーを返します。
func (ps PlayerSnapshot) Clone() PlayerSnapshot {
	clone := ps
	if ps.Stance != nil {
		stanceCopy := *ps.Stance
		clone.Stance = &stanceCopy
	}
	if ps.LastPositionID != nil {
		idCopy := *ps.LastPositionID
		clone.LastPositionID = &idCopy
	}
	return clone
}
