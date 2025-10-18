package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"server/internal/domain/entities"

	"github.com/google/uuid"
)

// UserRepositoryImpl はユーザーリポジトリの実装です
type UserRepositoryImpl struct {
	db *sql.DB
}

// NewUserRepository は新しいユーザーリポジトリを作成します
func NewUserRepository(db *sql.DB) *UserRepositoryImpl {
	return &UserRepositoryImpl{db: db}
}

// CreateUser は新しいユーザーを作成します
func (r *UserRepositoryImpl) CreateUser(ctx context.Context, user *entities.User) error {
	query := `
		INSERT INTO users (id, apple_id, email, full_name, hp, mp, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`

	_, err := r.db.ExecContext(ctx, query,
		user.ID,
		user.AppleID,
		user.Email,
		user.FullName,
		user.HP,
		user.MP,
		user.CreatedAt,
		user.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}

	return nil
}

// GetUserByAppleID はApple IDでユーザーを取得します
func (r *UserRepositoryImpl) GetUserByAppleID(ctx context.Context, appleID string) (*entities.User, error) {
	query := `
		SELECT id, apple_id, email, full_name, hp, mp, created_at, updated_at
		FROM users
		WHERE apple_id = $1
	`

	var user entities.User
	err := r.db.QueryRowContext(ctx, query, appleID).Scan(
		&user.ID,
		&user.AppleID,
		&user.Email,
		&user.FullName,
		&user.HP,
		&user.MP,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found")
		}
		return nil, fmt.Errorf("failed to get user by apple id: %w", err)
	}

	return &user, nil
}

// GetUserByID はIDでユーザーを取得します
func (r *UserRepositoryImpl) GetUserByID(ctx context.Context, id uuid.UUID) (*entities.User, error) {
	query := `
		SELECT id, apple_id, email, full_name, hp, mp, created_at, updated_at
		FROM users
		WHERE id = $1
	`

	var user entities.User
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&user.ID,
		&user.AppleID,
		&user.Email,
		&user.FullName,
		&user.HP,
		&user.MP,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found")
		}
		return nil, fmt.Errorf("failed to get user by id: %w", err)
	}

	return &user, nil
}

// UpdateUser はユーザー情報を更新します
func (r *UserRepositoryImpl) UpdateUser(ctx context.Context, user *entities.User) error {
	query := `
		UPDATE users
		SET email = $2, full_name = $3, hp = $4, mp = $5, updated_at = $6
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query,
		user.ID,
		user.Email,
		user.FullName,
		user.HP,
		user.MP,
		user.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to update user: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("user not found")
	}

	return nil
}

// UpdateUserHP はHPを更新します
func (r *UserRepositoryImpl) UpdateUserHP(ctx context.Context, userID uuid.UUID, hp int) error {
	query := `
		UPDATE users
		SET hp = $2, updated_at = $3
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query, userID, hp, time.Now())
	if err != nil {
		return fmt.Errorf("failed to update user hp: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("user not found")
	}

	return nil
}

// UpdateUserMP はMPを更新します
func (r *UserRepositoryImpl) UpdateUserMP(ctx context.Context, userID uuid.UUID, mp int) error {
	query := `
		UPDATE users
		SET mp = $2, updated_at = $3
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query, userID, mp, time.Now())
	if err != nil {
		return fmt.Errorf("failed to update user mp: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("user not found")
	}

	return nil
}
