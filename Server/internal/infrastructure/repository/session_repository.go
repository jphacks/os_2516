package repository

import (
	"context"
	"database/sql"
	"fmt"

	"server/internal/domain/entities"
)

// SessionRepositoryImpl はセッションリポジトリの実装です
type SessionRepositoryImpl struct {
	db *sql.DB
}

// NewSessionRepository は新しいセッションリポジトリを作成します
func NewSessionRepository(db *sql.DB) *SessionRepositoryImpl {
	return &SessionRepositoryImpl{db: db}
}

// CreateSession は新しいセッションを作成します
func (r *SessionRepositoryImpl) CreateSession(ctx context.Context, session *entities.Session) error {
	query := `
		INSERT INTO sessions (id, user_id, token, expires_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	_, err := r.db.ExecContext(ctx, query,
		session.ID,
		session.UserID,
		session.Token,
		session.ExpiresAt,
		session.CreatedAt,
		session.UpdatedAt,
	)

	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}

	return nil
}

// GetSessionByToken はトークンでセッションを取得します
func (r *SessionRepositoryImpl) GetSessionByToken(ctx context.Context, token string) (*entities.Session, error) {
	query := `
		SELECT id, user_id, token, expires_at, created_at, updated_at
		FROM sessions
		WHERE token = $1
	`

	var session entities.Session
	err := r.db.QueryRowContext(ctx, query, token).Scan(
		&session.ID,
		&session.UserID,
		&session.Token,
		&session.ExpiresAt,
		&session.CreatedAt,
		&session.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("session not found")
		}
		return nil, fmt.Errorf("failed to get session by token: %w", err)
	}

	return &session, nil
}

// DeleteSession はセッションを削除します
func (r *SessionRepositoryImpl) DeleteSession(ctx context.Context, token string) error {
	query := `DELETE FROM sessions WHERE token = $1`

	result, err := r.db.ExecContext(ctx, query, token)
	if err != nil {
		return fmt.Errorf("failed to delete session: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("session not found")
	}

	return nil
}

// DeleteExpiredSessions は期限切れのセッションを削除します
func (r *SessionRepositoryImpl) DeleteExpiredSessions(ctx context.Context) error {
	query := `DELETE FROM sessions WHERE expires_at < NOW()`

	_, err := r.db.ExecContext(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to delete expired sessions: %w", err)
	}

	return nil
}
