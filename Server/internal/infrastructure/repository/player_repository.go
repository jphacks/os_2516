package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"server/internal/domain/entities"

	"github.com/google/uuid"
)

// PlayerRepositoryImpl はプレイヤーリポジトリの実装です
type PlayerRepositoryImpl struct {
	db *sql.DB
}

// NewPlayerRepository は新しいプレイヤーリポジトリを作成します
func NewPlayerRepository(db *sql.DB) *PlayerRepositoryImpl {
	return &PlayerRepositoryImpl{db: db}
}

// CreatePlayer は新しいプレイヤーを作成します
func (r *PlayerRepositoryImpl) CreatePlayer(ctx context.Context, player *entities.Player) error {
	query := `
		INSERT INTO players (id, user_id, display_name, hp, mp, rank, avatar_url, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`

	_, err := r.db.ExecContext(ctx, query,
		player.ID,
		player.UserID,
		player.DisplayName,
		player.HP,
		player.MP,
		player.Rank,
		player.AvatarURL,
		player.CreatedAt,
		player.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to create player: %w", err)
	}

	return nil
}

// GetPlayerByUserID はユーザーIDでプレイヤーを取得します
func (r *PlayerRepositoryImpl) GetPlayerByUserID(ctx context.Context, userID uuid.UUID) (*entities.Player, error) {
	query := `
		SELECT id, user_id, display_name, hp, mp, rank, avatar_url, created_at, updated_at
		FROM players
		WHERE user_id = $1
	`

	var player entities.Player
	err := r.db.QueryRowContext(ctx, query, userID).Scan(
		&player.ID,
		&player.UserID,
		&player.DisplayName,
		&player.HP,
		&player.MP,
		&player.Rank,
		&player.AvatarURL,
		&player.CreatedAt,
		&player.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("player not found")
		}
		return nil, fmt.Errorf("failed to get player by user id: %w", err)
	}

	return &player, nil
}

// GetPlayerByID はIDでプレイヤーを取得します
func (r *PlayerRepositoryImpl) GetPlayerByID(ctx context.Context, id uuid.UUID) (*entities.Player, error) {
	query := `
		SELECT id, user_id, display_name, hp, mp, rank, avatar_url, created_at, updated_at
		FROM players
		WHERE id = $1
	`

	var player entities.Player
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&player.ID,
		&player.UserID,
		&player.DisplayName,
		&player.HP,
		&player.MP,
		&player.Rank,
		&player.AvatarURL,
		&player.CreatedAt,
		&player.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("player not found")
		}
		return nil, fmt.Errorf("failed to get player by id: %w", err)
	}

	return &player, nil
}

// UpdatePlayer はプレイヤー情報を更新します
func (r *PlayerRepositoryImpl) UpdatePlayer(ctx context.Context, player *entities.Player) error {
	query := `
		UPDATE players
		SET display_name = $2, hp = $3, mp = $4, rank = $5, avatar_url = $6, updated_at = $7
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query,
		player.ID,
		player.DisplayName,
		player.HP,
		player.MP,
		player.Rank,
		player.AvatarURL,
		player.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to update player: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("player not found")
	}

	return nil
}

// UpdatePlayerHP はHPを更新します
func (r *PlayerRepositoryImpl) UpdatePlayerHP(ctx context.Context, playerID uuid.UUID, hp int) error {
	query := `
		UPDATE players
		SET hp = $2, updated_at = $3
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query, playerID, hp, time.Now())
	if err != nil {
		return fmt.Errorf("failed to update player hp: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("player not found")
	}

	return nil
}

// UpdatePlayerMP はMPを更新します
func (r *PlayerRepositoryImpl) UpdatePlayerMP(ctx context.Context, playerID uuid.UUID, mp int) error {
	query := `
		UPDATE players
		SET mp = $2, updated_at = $3
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query, playerID, mp, time.Now())
	if err != nil {
		return fmt.Errorf("failed to update player mp: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("player not found")
	}

	return nil
}
