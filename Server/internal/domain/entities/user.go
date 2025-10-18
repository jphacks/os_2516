package entities

import (
	"time"

	"github.com/google/uuid"
)

// User はアプリケーションのユーザーを表すエンティティです
type User struct {
	ID        uuid.UUID `json:"id" db:"id"`
	AppleID   string    `json:"apple_id" db:"apple_id"`   // Apple ID（一意）
	Email     string    `json:"email" db:"email"`         // メールアドレス
	FullName  string    `json:"full_name" db:"full_name"` // フルネーム
	HP        int       `json:"hp" db:"hp"`               // ヒットポイント
	MP        int       `json:"mp" db:"mp"`               // マジックポイント
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

// NewUser は新しいユーザーを作成します
func NewUser(appleID, email, fullName string) *User {
	return &User{
		ID:        uuid.New(),
		AppleID:   appleID,
		Email:     email,
		FullName:  fullName,
		HP:        100, // デフォルトHP
		MP:        100, // デフォルトMP
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
}

// UpdateInfo はユーザー情報を更新します
func (u *User) UpdateInfo(email, fullName string) {
	u.Email = email
	u.FullName = fullName
	u.UpdatedAt = time.Now()
}

// UpdateHP はHPを更新します
func (u *User) UpdateHP(hp int) {
	u.HP = hp
	u.UpdatedAt = time.Now()
}

// UpdateMP はMPを更新します
func (u *User) UpdateMP(mp int) {
	u.MP = mp
	u.UpdatedAt = time.Now()
}
