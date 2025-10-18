package auth

import (
	"context"
	"fmt"
	"strings"

	"server/internal/domain/entities"

	"github.com/google/uuid"
)

// MockUserRepository はテスト用のユーザーリポジトリです
type MockUserRepository struct {
	users map[string]*entities.User
}

// NewMockUserRepository は新しいモックユーザーリポジトリを作成します
func NewMockUserRepository() *MockUserRepository {
	return &MockUserRepository{
		users: make(map[string]*entities.User),
	}
}

func (m *MockUserRepository) CreateUser(ctx context.Context, user *entities.User) error {
	email := strings.ToLower(user.Email)
	m.users[email] = user
	return nil
}

func (m *MockUserRepository) GetUserByEmail(ctx context.Context, email string) (*entities.User, error) {
	user, exists := m.users[strings.ToLower(email)]
	if !exists {
		return nil, fmt.Errorf("user not found")
	}
	return user, nil
}

func (m *MockUserRepository) GetUserByID(ctx context.Context, id uuid.UUID) (*entities.User, error) {
	for _, user := range m.users {
		if user.ID == id {
			return user, nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func (m *MockUserRepository) UpdateUser(ctx context.Context, user *entities.User) error {
	m.users[strings.ToLower(user.Email)] = user
	return nil
}
