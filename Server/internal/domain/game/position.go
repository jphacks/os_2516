package game

import (
	"time"

	"github.com/google/uuid"
)

// Coordinate は地理座標を表します。
type Coordinate struct {
	Latitude  float64
	Longitude float64
	Altitude  *float64
}

// PositionAccuracy は座標や方位の精度情報を保持します。
type PositionAccuracy struct {
	Horizontal float64
	Vertical   *float64
	Heading    *float64
}

// PlayerPosition はセッション内プレイヤーの最新座標を表します。
type PlayerPosition struct {
	SessionID  uuid.UUID
	PlayerID   uuid.UUID
	Coordinate Coordinate
	Heading    float64
	Accuracy   PositionAccuracy
	RecordedAt time.Time
}

// Clone は座標情報のコピーを返します。
func (pp PlayerPosition) Clone() PlayerPosition {
	clone := pp
	if pp.Coordinate.Altitude != nil {
		alt := *pp.Coordinate.Altitude
		clone.Coordinate.Altitude = &alt
	}
	if pp.Accuracy.Vertical != nil {
		vert := *pp.Accuracy.Vertical
		clone.Accuracy.Vertical = &vert
	}
	if pp.Accuracy.Heading != nil {
		head := *pp.Accuracy.Heading
		clone.Accuracy.Heading = &head
	}
	return clone
}

// AttackRequest は攻撃処理に必要な情報を表します。
type AttackRequest struct {
	SessionID   uuid.UUID
	AttackerID  uuid.UUID
	TargetID    uuid.UUID
	AttackID    uuid.UUID
	ChargeLevel int
	Position    PlayerPosition
}

// AttackOutcome は攻撃判定結果を表します。
type AttackOutcome struct {
	Request AttackRequest
	Hit     bool
	Damage  int
}
