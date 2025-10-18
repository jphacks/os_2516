package auth

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"server/internal/domain/entities"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type contextKey string

const (
	UserIDKey  contextKey = "user_id"
	sessionKey contextKey = "session"
)

// AuthMiddleware は認証ミドルウェアです
type AuthMiddleware struct {
	jwtSecret   string
	sessionRepo SessionRepository
}

// NewAuthMiddleware は新しい認証ミドルウェアを作成します
func NewAuthMiddleware(jwtSecret string, sessionRepo SessionRepository) *AuthMiddleware {
	return &AuthMiddleware{
		jwtSecret:   jwtSecret,
		sessionRepo: sessionRepo,
	}
}

// RequireAuth は認証が必要なエンドポイント用のミドルウェアです
func (m *AuthMiddleware) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Authorizationヘッダーからトークンを取得
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Authorization header required", http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == authHeader {
			http.Error(w, "Invalid authorization header format", http.StatusUnauthorized)
			return
		}

		// JWTトークンを検証
		claims, err := m.validateToken(token)
		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		// セッションの存在確認
		session, err := m.sessionRepo.GetSessionByToken(r.Context(), token)
		if err != nil {
			http.Error(w, "Session not found", http.StatusUnauthorized)
			return
		}

		if session.IsExpired() {
			http.Error(w, "Session expired", http.StatusUnauthorized)
			return
		}

		// ユーザーIDをコンテキストに追加
		userID, err := uuid.Parse(claims["user_id"].(string))
		if err != nil {
			http.Error(w, "Invalid user ID in token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserIDKey, userID)
		ctx = context.WithValue(ctx, sessionKey, session)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// validateToken はJWTトークンを検証します
func (m *AuthMiddleware) validateToken(tokenString string) (jwt.MapClaims, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		// 署名方法の確認
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(m.jwtSecret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, fmt.Errorf("invalid token")
}

// GetUserIDFromContext はコンテキストからユーザーIDを取得します
func GetUserIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	userID, ok := ctx.Value(UserIDKey).(uuid.UUID)
	return userID, ok
}

// GetSessionFromContext はコンテキストからセッションを取得します
func GetSessionFromContext(ctx context.Context) (*entities.Session, bool) {
	session, ok := ctx.Value(sessionKey).(*entities.Session)
	return session, ok
}
