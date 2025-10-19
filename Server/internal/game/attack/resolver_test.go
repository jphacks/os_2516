package attack

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"server/internal/domain/game"
)

func TestResolverResolveHitWithinRangeAndAngle(t *testing.T) {
	resolver := NewDefaultResolver()

	attackerID := uuid.New()
	targetID := uuid.New()
	sessionID := uuid.New()

	now := time.Now().UTC()

	attackerPosition := game.PlayerPosition{
		SessionID: sessionID,
		PlayerID:  attackerID,
		Coordinate: game.Coordinate{
			Latitude:  35.0,
			Longitude: 139.0,
		},
		Heading:    90.0,
		RecordedAt: now,
	}

	targetPosition := &game.PlayerPosition{
		SessionID: sessionID,
		PlayerID:  targetID,
		Coordinate: game.Coordinate{
			Latitude:  35.0,
			Longitude: 139.000015,
		},
		RecordedAt: now,
	}

	request := game.AttackRequest{
		SessionID:   sessionID,
		AttackerID:  attackerID,
		TargetID:    targetID,
		AttackID:    uuid.New(),
		ChargeLevel: 0,
		Position:    attackerPosition,
	}

	outcome, err := resolver.Resolve(request, attackerPosition, targetPosition)
	if err != nil {
		t.Fatalf("resolver returned error: %v", err)
	}
	if !outcome.Hit {
		t.Fatalf("expected hit to be true")
	}
	if outcome.Damage != resolver.BaseDamage {
		t.Fatalf("unexpected damage: got %d want %d", outcome.Damage, resolver.BaseDamage)
	}
}

func TestResolverResolveMissByAngle(t *testing.T) {
	resolver := NewDefaultResolver()

	now := time.Now().UTC()

	attackerPosition := game.PlayerPosition{
		Coordinate: game.Coordinate{Latitude: 35.0, Longitude: 139.0},
		Heading:    0.0,
		RecordedAt: now,
	}
	targetPosition := &game.PlayerPosition{
		Coordinate: game.Coordinate{Latitude: 35.0, Longitude: 139.00002},
		RecordedAt: now,
	}

	request := game.AttackRequest{Position: attackerPosition}

	outcome, err := resolver.Resolve(request, attackerPosition, targetPosition)
	if err != nil {
		t.Fatalf("resolver returned error: %v", err)
	}
	if outcome.Hit {
		t.Fatalf("expected hit to be false when angle difference exceeds tolerance")
	}
}

func TestResolverResolveMissByExpiredTarget(t *testing.T) {
	resolver := NewDefaultResolver()
	resolver.PositionExpiry = 500 * time.Millisecond

	now := time.Now().UTC()

	attackerPosition := game.PlayerPosition{
		Coordinate: game.Coordinate{Latitude: 35.0, Longitude: 139.0},
		Heading:    90.0,
		RecordedAt: now,
	}
	targetPosition := &game.PlayerPosition{
		Coordinate: game.Coordinate{Latitude: 35.0, Longitude: 139.00002},
		RecordedAt: now.Add(-1 * time.Second),
	}

	request := game.AttackRequest{Position: attackerPosition}

	outcome, err := resolver.Resolve(request, attackerPosition, targetPosition)
	if err != nil {
		t.Fatalf("resolver returned error: %v", err)
	}
	if outcome.Hit {
		t.Fatalf("expected hit to be false when target position is stale")
	}
}
