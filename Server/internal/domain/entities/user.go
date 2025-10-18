package entities

import (
	"time"

	"github.com/google/uuid"
)

// User はアプリケーションのユーザーを表すエンティティです
type User struct {
	ID           uuid.UUID `json:"id" db:"id"`
	Email        string    `json:"email" db:"email"`         // メールアドレス（一意）
	PasswordHash string    `json:"-" db:"password_hash"`     // ハッシュ化済みパスワード
	FullName     string    `json:"full_name" db:"full_name"` // フルネーム
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time `json:"updated_at" db:"updated_at"`
}

// NewUser は新しいユーザーを作成します
func NewUser(email, passwordHash, fullName string) *User {
	return &User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: passwordHash,
		FullName:     fullName,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
}

// UpdateInfo はユーザー情報を更新します
func (u *User) UpdateInfo(email, fullName string) {
	u.Email = email
	u.FullName = fullName
	u.UpdatedAt = time.Now()
}
