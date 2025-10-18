package repository

import (
	"context"
	"database/sql"
	"fmt"

	appdomain "server/internal/domain/battlestage"
	"server/internal/supabase"
)

// BattleStageSupabaseRepository は Supabase Postgres を利用したバトルステージリポジトリです。
type BattleStageSupabaseRepository struct {
	client supabase.Client
}

// NewBattleStageSupabaseRepository は Supabase クライアントを用いたリポジトリを生成します。
func NewBattleStageSupabaseRepository(client supabase.Client) *BattleStageSupabaseRepository {
	return &BattleStageSupabaseRepository{client: client}
}

// FindNearby はハーサイン式を用いて半径内のステージを検索します。
func (r *BattleStageSupabaseRepository) FindNearby(ctx context.Context, origin appdomain.Location, radiusMeters float64) ([]appdomain.StageWithDistance, error) {
	if r.client == nil || !r.client.Ready() {
		return nil, fmt.Errorf("supabase client not ready")
	}

	const query = `
WITH stage_distance AS (
    SELECT
        id::text AS id,
        name,
        latitude,
        longitude,
        radius_m,
        description,
        6371000 * acos(
            LEAST(1, GREATEST(-1,
                cos(radians($1)) * cos(radians(latitude)) * cos(radians(longitude) - radians($2)) +
                sin(radians($1)) * sin(radians(latitude))
            ))
        ) AS distance_m
    FROM public.battle_stages
)
SELECT id, name, latitude, longitude, radius_m, description, distance_m
FROM stage_distance
WHERE distance_m <= $3
ORDER BY distance_m ASC
LIMIT 100;
`

	rows, err := r.client.Query(ctx, query, origin.Latitude, origin.Longitude, radiusMeters)
	if err != nil {
		return nil, fmt.Errorf("query nearby battle stages: %w", err)
	}
	defer rows.Close()

	stages := make([]appdomain.StageWithDistance, 0)
	for rows.Next() {
		var (
			id, name            string
			latitude, longitude float64
			radiusValue         sql.NullFloat64
			descriptionValue    sql.NullString
			distance            float64
		)

		if err := rows.Scan(&id, &name, &latitude, &longitude, &radiusValue, &descriptionValue, &distance); err != nil {
			return nil, fmt.Errorf("scan battle stage: %w", err)
		}

		stage := appdomain.Stage{
			ID:       id,
			Name:     name,
			Location: appdomain.Location{Latitude: latitude, Longitude: longitude},
		}

		if radiusValue.Valid {
			value := radiusValue.Float64
			stage.RadiusMeters = &value
		}

		if descriptionValue.Valid {
			value := descriptionValue.String
			stage.Description = &value
		}

		stages = append(stages, appdomain.StageWithDistance{
			Stage:          stage,
			DistanceMeters: distance,
		})
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate battle stages: %w", err)
	}

	return stages, nil
}
