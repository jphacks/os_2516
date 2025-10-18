package entities

import (
	"time"

	"github.com/google/uuid"
)

// Player はゲーム内のプレイヤーを表すエンティティです
type Player struct {
	ID          uuid.UUID  `json:"id" db:"id"`
	UserID      *uuid.UUID `json:"user_id" db:"user_id"`           // ユーザーID（ゲストはNULL可）
	DisplayName string     `json:"display_name" db:"display_name"` // 表示名
	HP          int        `json:"hp" db:"hp"`                     // ヒットポイント
	MP          int        `json:"mp" db:"mp"`                     // マジックポイント
	Rank        int        `json:"rank" db:"rank"`                 // レーティング
	AvatarURL   *string    `json:"avatar_url" db:"avatar_url"`     // アバター画像URL
	CreatedAt   time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at" db:"updated_at"`
}

// NewPlayer は新しいプレイヤーを作成します
func NewPlayer(userID *uuid.UUID, displayName string) *Player {
	return &Player{
		ID:          uuid.New(),
		UserID:      userID,
		DisplayName: displayName,
		HP:          100, // デフォルトHP
		MP:          100, // デフォルトMP
		Rank:        0,   // デフォルトランク
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
}

// UpdateDisplayName は表示名を更新します
func (p *Player) UpdateDisplayName(displayName string) {
	p.DisplayName = displayName
	p.UpdatedAt = time.Now()
}

// UpdateHP はHPを更新します
func (p *Player) UpdateHP(hp int) {
	p.HP = hp
	p.UpdatedAt = time.Now()
}

// UpdateMP はMPを更新します
func (p *Player) UpdateMP(mp int) {
	p.MP = mp
	p.UpdatedAt = time.Now()
}

// UpdateRank はランクを更新します
func (p *Player) UpdateRank(rank int) {
	p.Rank = rank
	p.UpdatedAt = time.Now()
}

// UpdateAvatar はアバターURLを更新します
func (p *Player) UpdateAvatar(avatarURL *string) {
	p.AvatarURL = avatarURL
	p.UpdatedAt = time.Now()
}
