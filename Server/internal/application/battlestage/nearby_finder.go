package battlestage

import (
	"context"

	domain "server/internal/domain/battlestage"
)

// NearbyFinder は指定地点周辺のステージ取得ユースケースを表現します。
type NearbyFinder struct {
	repo         domain.Repository
	searchRadius float64
}

// NewNearbyFinder はユースケースを生成します。
func NewNearbyFinder(repo domain.Repository, searchRadius float64) *NearbyFinder {
	return &NearbyFinder{repo: repo, searchRadius: searchRadius}
}

// Execute は指定地点から searchRadius 以内のステージ一覧を取得します。
func (f *NearbyFinder) Execute(ctx context.Context, location domain.Location) ([]domain.StageWithDistance, error) {
	return f.repo.FindNearby(ctx, location, f.searchRadius)
}

// SearchRadius はユースケースが利用する検索半径を返します。
func (f *NearbyFinder) SearchRadius() float64 {
	return f.searchRadius
}
