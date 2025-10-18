package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"server/internal/domain/entities"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// MockSessionRepository はテスト用のセッションリポジトリです
type MockSessionRepository struct {
	sessions map[string]*entities.Session
}

func NewMockSessionRepository() *MockSessionRepository {
	return &MockSessionRepository{
		sessions: make(map[string]*entities.Session),
	}
}

func (m *MockSessionRepository) CreateSession(ctx context.Context, session *entities.Session) error {
	m.sessions[session.Token] = session
	return nil
}

func (m *MockSessionRepository) GetSessionByToken(ctx context.Context, token string) (*entities.Session, error) {
	session, exists := m.sessions[token]
	if !exists {
		return nil, fmt.Errorf("session not found")
	}
	return session, nil
}

func (m *MockSessionRepository) DeleteSession(ctx context.Context, token string) error {
	delete(m.sessions, token)
	return nil
}

func (m *MockSessionRepository) DeleteExpiredSessions(ctx context.Context) error {
	for token, session := range m.sessions {
		if session.IsExpired() {
			delete(m.sessions, token)
		}
	}
	return nil
}

func TestAuthHandler_HandleSignUp_Success(t *testing.T) {
	userRepo := NewMockUserRepository()
	sessionRepo := NewMockSessionRepository()
	playerRepo := NewMockPlayerRepository()
	handler := NewAuthHandler(userRepo, playerRepo, sessionRepo, "test-secret")

	reqBody := SignUpRequest{
		Email:    "NewUser@example.com",
		Password: "Passw0rd!",
		FullName: "New User",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/auth/signup", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	handler.HandleSignUp(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, w.Code)
	}

	var resp SignInResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.AccessToken == "" {
		t.Error("expected access token in response")
	}

	if resp.User == nil || resp.User.Email != "newuser@example.com" {
		t.Errorf("expected user email to be normalized, got %+v", resp.User)
	}

	storedUser, err := userRepo.GetUserByEmail(context.Background(), "newuser@example.com")
	if err != nil {
		t.Fatalf("expected user stored, got error: %v", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(storedUser.PasswordHash), []byte("Passw0rd!")); err != nil {
		t.Fatalf("stored password hash does not match original password: %v", err)
	}
}

func TestAuthHandler_HandleSignIn(t *testing.T) {
	userRepo := NewMockUserRepository()
	sessionRepo := NewMockSessionRepository()
	playerRepo := NewMockPlayerRepository()
	handler := NewAuthHandler(userRepo, playerRepo, sessionRepo, "test-secret")

	hashed, err := bcrypt.GenerateFromPassword([]byte("Passw0rd!"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash password: %v", err)
	}

	user := entities.NewUser("existing@example.com", string(hashed), "Existing User")
	if err := userRepo.CreateUser(context.Background(), user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	t.Run("successful sign in", func(t *testing.T) {
		reqBody := SignInRequest{Email: "existing@example.com", Password: "Passw0rd!"}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/auth/signin", bytes.NewBuffer(body))
		req.Header.Set("Content-Type", "application/json")

		w := httptest.NewRecorder()
		handler.HandleSignIn(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected status %d, got %d", http.StatusOK, w.Code)
		}

		var resp SignInResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}

		if resp.AccessToken == "" {
			t.Error("expected access token in response")
		}
	})

	t.Run("invalid password", func(t *testing.T) {
		reqBody := SignInRequest{Email: "existing@example.com", Password: "wrong"}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/auth/signin", bytes.NewBuffer(body))
		req.Header.Set("Content-Type", "application/json")

		w := httptest.NewRecorder()
		handler.HandleSignIn(w, req)

		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected status %d, got %d", http.StatusUnauthorized, w.Code)
		}
	})
}

func TestAuthHandler_HandleLogout(t *testing.T) {
	userRepo := NewMockUserRepository()
	sessionRepo := NewMockSessionRepository()
	playerRepo := NewMockPlayerRepository()
	handler := NewAuthHandler(userRepo, playerRepo, sessionRepo, "test-secret")

	tests := []struct {
		name           string
		authHeader     string
		expectedStatus int
	}{
		{
			name:           "missing authorization header",
			authHeader:     "",
			expectedStatus: http.StatusUnauthorized,
		},
		{
			name:           "invalid authorization header format",
			authHeader:     "InvalidFormat token123",
			expectedStatus: http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}

			w := httptest.NewRecorder()

			handler.HandleLogout(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("expected status %d, got %d", tt.expectedStatus, w.Code)
			}
		})
	}
}

func TestAuthHandler_GenerateAccessToken(t *testing.T) {
	handler := &AuthHandler{
		jwtSecret: "test-secret",
	}

	userID := uuid.New()
	token, expiresAt, err := handler.generateAccessToken(userID)

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if token == "" {
		t.Error("expected non-empty token")
	}

	if time.Until(expiresAt) < 23*time.Hour {
		t.Error("expected token to be valid for at least 23 hours")
	}
}
