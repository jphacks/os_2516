package battlestage

import "context"

// Location は地理座標を表現します。
type Location struct {
	Latitude  float64
	Longitude float64
}

// Stage は対戦ステージのメタデータを保持します。
type Stage struct {
	ID           string
	Name         string
	Location     Location
	RadiusMeters *float64
	Description  *string
}

// StageWithDistance は検索地点からの距離を付与したステージ情報です。
type StageWithDistance struct {
	Stage          Stage
	DistanceMeters float64
}

// Repository はステージ情報の取得を抽象化します。
type Repository interface {
	FindNearby(ctx context.Context, origin Location, radiusMeters float64) ([]StageWithDistance, error)
}
