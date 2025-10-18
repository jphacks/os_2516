package repository

import (
	"context"
	"database/sql"
	"fmt"

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
		INSERT INTO users (id, email, password_hash, full_name, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	_, err := r.db.ExecContext(ctx, query,
		user.ID,
		user.Email,
		user.PasswordHash,
		user.FullName,
		user.CreatedAt,
		user.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}

	return nil
}

// GetUserByEmail はメールアドレスでユーザーを取得します
func (r *UserRepositoryImpl) GetUserByEmail(ctx context.Context, email string) (*entities.User, error) {
	query := `
		SELECT id, email, password_hash, full_name, created_at, updated_at
		FROM users
		WHERE email = $1
	`

	var user entities.User
	err := r.db.QueryRowContext(ctx, query, email).Scan(
		&user.ID,
		&user.Email,
		&user.PasswordHash,
		&user.FullName,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found")
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}

	return &user, nil
}

// GetUserByID はIDでユーザーを取得します
func (r *UserRepositoryImpl) GetUserByID(ctx context.Context, id uuid.UUID) (*entities.User, error) {
	query := `
		SELECT id, email, password_hash, full_name, created_at, updated_at
		FROM users
		WHERE id = $1
	`

	var user entities.User
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&user.ID,
		&user.Email,
		&user.PasswordHash,
		&user.FullName,
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
		SET email = $2, full_name = $3, updated_at = $4
		WHERE id = $1
	`

	result, err := r.db.ExecContext(ctx, query,
		user.ID,
		user.Email,
		user.FullName,
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
