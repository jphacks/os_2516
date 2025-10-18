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

func TestAuthHandler_HandleAppleSignIn(t *testing.T) {
	// モックリポジトリを作成
	userRepo := NewMockUserRepository()
	sessionRepo := NewMockSessionRepository()

	// Apple認証サービス（実際の検証は行わない）
	appleService := NewAppleAuthService("com.test.app", "TEAM123", "KEY123")

	// 認証ハンドラーを作成
	handler := NewAuthHandler(appleService, userRepo, sessionRepo, "test-secret")

	tests := []struct {
		name           string
		requestBody    SignInRequest
		expectedStatus int
	}{
		{
			name: "missing id_token",
			requestBody: SignInRequest{
				IDToken: "",
			},
			expectedStatus: http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// リクエストボディを作成
			body, _ := json.Marshal(tt.requestBody)
			req := httptest.NewRequest(http.MethodPost, "/auth/apple/signin", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")

			// レスポンスレコーダーを作成
			w := httptest.NewRecorder()

			// ハンドラーを実行
			handler.HandleAppleSignIn(w, req)

			// ステータスコードを確認
			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}
		})
	}
}

func TestAuthHandler_HandleLogout(t *testing.T) {
	// モックリポジトリを作成
	userRepo := NewMockUserRepository()
	sessionRepo := NewMockSessionRepository()

	// Apple認証サービス
	appleService := NewAppleAuthService("com.test.app", "TEAM123", "KEY123")

	// 認証ハンドラーを作成
	handler := NewAuthHandler(appleService, userRepo, sessionRepo, "test-secret")

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
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
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
		t.Fatalf("Expected no error, got %v", err)
	}

	if token == "" {
		t.Error("Expected non-empty token")
	}

	if time.Until(expiresAt) < 23*time.Hour {
		t.Error("Expected token to be valid for at least 23 hours")
	}
}
