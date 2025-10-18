package auth

import (
	"context"
	"fmt"
	"time"

	"server/internal/domain/entities"

	"github.com/google/uuid"
)

// MockPlayerRepository はテスト用のプレイヤーリポジトリです
type MockPlayerRepository struct {
	players map[uuid.UUID]*entities.Player
}

// NewMockPlayerRepository は新しいモックプレイヤーリポジトリを作成します
func NewMockPlayerRepository() *MockPlayerRepository {
	return &MockPlayerRepository{
		players: make(map[uuid.UUID]*entities.Player),
	}
}

func (m *MockPlayerRepository) CreatePlayer(ctx context.Context, player *entities.Player) error {
	m.players[player.ID] = player
	return nil
}

func (m *MockPlayerRepository) GetPlayerByUserID(ctx context.Context, userID uuid.UUID) (*entities.Player, error) {
	for _, player := range m.players {
		if player.UserID != nil && *player.UserID == userID {
			return player, nil
		}
	}
	return nil, fmt.Errorf("player not found")
}

func (m *MockPlayerRepository) GetPlayerByID(ctx context.Context, id uuid.UUID) (*entities.Player, error) {
	player, exists := m.players[id]
	if !exists {
		return nil, fmt.Errorf("player not found")
	}
	return player, nil
}

func (m *MockPlayerRepository) UpdatePlayer(ctx context.Context, player *entities.Player) error {
	if _, exists := m.players[player.ID]; !exists {
		return fmt.Errorf("player not found")
	}
	m.players[player.ID] = player
	return nil
}

func (m *MockPlayerRepository) UpdatePlayerHP(ctx context.Context, playerID uuid.UUID, hp int) error {
	player, exists := m.players[playerID]
	if !exists {
		return fmt.Errorf("player not found")
	}
	player.HP = hp
	player.UpdatedAt = time.Now()
	return nil
}

func (m *MockPlayerRepository) UpdatePlayerMP(ctx context.Context, playerID uuid.UUID, mp int) error {
	player, exists := m.players[playerID]
	if !exists {
		return fmt.Errorf("player not found")
	}
	player.MP = mp
	player.UpdatedAt = time.Now()
	return nil
}
