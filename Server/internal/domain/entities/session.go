package entities

import (
	"time"

	"github.com/google/uuid"
)

// Session はユーザーの認証セッションを表すエンティティです
type Session struct {
	ID        uuid.UUID `json:"id" db:"id"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	Token     string    `json:"token" db:"token"`           // JWTトークン
	ExpiresAt time.Time `json:"expires_at" db:"expires_at"` // 有効期限
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

// NewSession は新しいセッションを作成します
func NewSession(userID uuid.UUID, token string, expiresAt time.Time) *Session {
	return &Session{
		ID:        uuid.New(),
		UserID:    userID,
		Token:     token,
		ExpiresAt: expiresAt,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
}

// IsExpired はセッションが期限切れかどうかを確認します
func (s *Session) IsExpired() bool {
	return time.Now().After(s.ExpiresAt)
}

// Extend はセッションの有効期限を延長します
func (s *Session) Extend(newExpiresAt time.Time) {
	s.ExpiresAt = newExpiresAt
	s.UpdatedAt = time.Now()
}
