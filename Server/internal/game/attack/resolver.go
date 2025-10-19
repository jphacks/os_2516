package attack

import (
	"errors"
	"math"
	"time"

	"server/internal/domain/game"
)

const (
	earthRadiusMeters = 6371000.0
)

// Resolver は攻撃判定ロジックをカプセル化します。
type Resolver struct {
	BaseRangeMeters   float64
	ChargeRangeBonus  float64
	BaseDamage        int
	ChargeDamageBonus int
	AngleToleranceDeg float64
	PositionExpiry    time.Duration
}

// NewDefaultResolver はシンプルなデフォルト設定の Resolver を生成します。
func NewDefaultResolver() *Resolver {
	return &Resolver{
		BaseRangeMeters:   2.5,
		ChargeRangeBonus:  0.5,
		BaseDamage:        20,
		ChargeDamageBonus: 5,
		AngleToleranceDeg: 30,
		PositionExpiry:    750 * time.Millisecond,
	}
}

// Resolve は攻撃リクエストに対して命中判定を行います。
func (r *Resolver) Resolve(request game.AttackRequest, attacker game.PlayerPosition, target *game.PlayerPosition) (game.AttackOutcome, error) {
	if r == nil {
		return game.AttackOutcome{Request: request}, errors.New("attack resolver not configured")
	}

	outcome := game.AttackOutcome{Request: request}

	if target == nil {
		return outcome, nil
	}

	now := request.Position.RecordedAt
	if now.IsZero() {
		now = time.Now()
	}

	if !target.RecordedAt.IsZero() && r.PositionExpiry > 0 {
		if now.Sub(target.RecordedAt) > r.PositionExpiry {
			return outcome, nil
		}
	}

	distance := haversineMeters(attacker.Coordinate, target.Coordinate)
	maxRange := r.BaseRangeMeters + (float64(request.ChargeLevel) * r.ChargeRangeBonus)
	if distance > maxRange {
		return outcome, nil
	}

	bearing := bearingDegrees(attacker.Coordinate, target.Coordinate)
	headingDiff := angleDifferenceDegrees(request.Position.Heading, bearing)
	if headingDiff > r.AngleToleranceDeg {
		return outcome, nil
	}

	outcome.Hit = true
	outcome.Damage = r.BaseDamage + (request.ChargeLevel * r.ChargeDamageBonus)
	return outcome, nil
}

func haversineMeters(a, b game.Coordinate) float64 {
	lat1 := degreesToRadians(a.Latitude)
	lat2 := degreesToRadians(b.Latitude)
	dLat := degreesToRadians(b.Latitude - a.Latitude)
	dLon := degreesToRadians(b.Longitude - a.Longitude)

	sinLat := math.Sin(dLat / 2)
	sinLon := math.Sin(dLon / 2)
	h := sinLat*sinLat + math.Cos(lat1)*math.Cos(lat2)*sinLon*sinLon
	return 2 * earthRadiusMeters * math.Asin(math.Sqrt(h))
}

func bearingDegrees(a, b game.Coordinate) float64 {
	lat1 := degreesToRadians(a.Latitude)
	lat2 := degreesToRadians(b.Latitude)
	dLon := degreesToRadians(b.Longitude - a.Longitude)

	y := math.Sin(dLon) * math.Cos(lat2)
	x := math.Cos(lat1)*math.Sin(lat2) - math.Sin(lat1)*math.Cos(lat2)*math.Cos(dLon)
	bearing := radiansToDegrees(math.Atan2(y, x))
	return normalizeDegrees(bearing)
}

func angleDifferenceDegrees(a, b float64) float64 {
	diff := math.Mod(math.Abs(a-b), 360)
	if diff > 180 {
		diff = 360 - diff
	}
	return diff
}

func degreesToRadians(deg float64) float64 {
	return deg * math.Pi / 180.0
}

func radiansToDegrees(rad float64) float64 {
	return rad * 180.0 / math.Pi
}

func normalizeDegrees(deg float64) float64 {
	result := math.Mod(deg, 360)
	if result < 0 {
		result += 360
	}
	return result
}
