package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"server/internal/domain/entities"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// PlayerRepository はプレイヤーリポジトリのインターフェースです
type PlayerRepository interface {
	CreatePlayer(ctx context.Context, player *entities.Player) error
	GetPlayerByUserID(ctx context.Context, userID uuid.UUID) (*entities.Player, error)
}

// AuthHandler は認証関連のHTTPハンドラーです
type AuthHandler struct {
	appleService *AppleAuthService
	userRepo     UserRepository
	playerRepo   PlayerRepository
	sessionRepo  SessionRepository
	jwtSecret    string
}

// UserRepository はユーザーリポジトリのインターフェースです
type UserRepository interface {
	CreateUser(ctx context.Context, user *entities.User) error
	GetUserByAppleID(ctx context.Context, appleID string) (*entities.User, error)
	GetUserByID(ctx context.Context, id uuid.UUID) (*entities.User, error)
	UpdateUser(ctx context.Context, user *entities.User) error
}

// SessionRepository はセッションリポジトリのインターフェースです
type SessionRepository interface {
	CreateSession(ctx context.Context, session *entities.Session) error
	GetSessionByToken(ctx context.Context, token string) (*entities.Session, error)
	DeleteSession(ctx context.Context, token string) error
	DeleteExpiredSessions(ctx context.Context) error
}

// NewAuthHandler は新しい認証ハンドラーを作成します
func NewAuthHandler(appleService *AppleAuthService, userRepo UserRepository, playerRepo PlayerRepository, sessionRepo SessionRepository, jwtSecret string) *AuthHandler {
	return &AuthHandler{
		appleService: appleService,
		userRepo:     userRepo,
		playerRepo:   playerRepo,
		sessionRepo:  sessionRepo,
		jwtSecret:    jwtSecret,
	}
}

// SignInRequest Apple Sign Inリクエスト
type SignInRequest struct {
	IDToken string `json:"id_token" validate:"required"`
}

// SignInResponse Apple Sign Inレスポンス
type SignInResponse struct {
	AccessToken string    `json:"access_token"`
	User        *UserInfo `json:"user"`
	ExpiresIn   int64     `json:"expires_in"`
}

// UserInfo ユーザー情報
type UserInfo struct {
	ID       uuid.UUID `json:"id"`
	AppleID  string    `json:"apple_id"`
	Email    string    `json:"email"`
	FullName string    `json:"full_name"`
}

// HandleAppleSignIn Apple Sign Inを処理します
func (h *AuthHandler) HandleAppleSignIn(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SignInRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// Apple ID Tokenを検証
	claims, err := h.appleService.VerifyIDToken(ctx, req.IDToken)
	if err != nil {
		http.Error(w, fmt.Sprintf("Token verification failed: %v", err), http.StatusUnauthorized)
		return
	}

	// ユーザーを取得または作成
	user, err := h.userRepo.GetUserByAppleID(ctx, claims.Sub)
	if err != nil {
		// ユーザーが存在しない場合は新規作成
		user = entities.NewUser(claims.Sub, claims.Email, "")
		if err := h.userRepo.CreateUser(ctx, user); err != nil {
			http.Error(w, "Failed to create user", http.StatusInternalServerError)
			return
		}

		// 新規ユーザーの場合はプレイヤーも作成
		player := entities.NewPlayer(&user.ID, user.FullName)
		if err := h.playerRepo.CreatePlayer(ctx, player); err != nil {
			http.Error(w, "Failed to create player", http.StatusInternalServerError)
			return
		}
	} else {
		// 既存ユーザーの情報を更新（メールアドレスが変更されている可能性）
		if claims.Email != "" && claims.Email != user.Email {
			user.UpdateInfo(claims.Email, user.FullName)
			if err := h.userRepo.UpdateUser(ctx, user); err != nil {
				http.Error(w, "Failed to update user", http.StatusInternalServerError)
				return
			}
		}
	}

	// セッション用のJWTトークンを生成
	accessToken, expiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate access token", http.StatusInternalServerError)
		return
	}

	// セッションをデータベースに保存
	session := entities.NewSession(user.ID, accessToken, expiresAt)
	if err := h.sessionRepo.CreateSession(ctx, session); err != nil {
		http.Error(w, "Failed to create session", http.StatusInternalServerError)
		return
	}

	// レスポンスを返す
	response := SignInResponse{
		AccessToken: accessToken,
		User: &UserInfo{
			ID:       user.ID,
			AppleID:  user.AppleID,
			Email:    user.Email,
			FullName: user.FullName,
		},
		ExpiresIn: int64(time.Until(expiresAt).Seconds()),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// HandleRefresh トークンリフレッシュを処理します
func (h *AuthHandler) HandleRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

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

	ctx := r.Context()

	// セッションを検証
	session, err := h.sessionRepo.GetSessionByToken(ctx, token)
	if err != nil {
		http.Error(w, "Invalid session", http.StatusUnauthorized)
		return
	}

	if session.IsExpired() {
		http.Error(w, "Session expired", http.StatusUnauthorized)
		return
	}

	// ユーザー情報を取得
	user, err := h.userRepo.GetUserByID(ctx, session.UserID)
	if err != nil {
		http.Error(w, "User not found", http.StatusUnauthorized)
		return
	}

	// 新しいトークンを生成
	newAccessToken, newExpiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate new access token", http.StatusInternalServerError)
		return
	}

	// 古いセッションを削除
	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		// ログに記録するが、処理は続行
	}

	// 新しいセッションを作成
	newSession := entities.NewSession(user.ID, newAccessToken, newExpiresAt)
	if err := h.sessionRepo.CreateSession(ctx, newSession); err != nil {
		http.Error(w, "Failed to create new session", http.StatusInternalServerError)
		return
	}

	// レスポンスを返す
	response := SignInResponse{
		AccessToken: newAccessToken,
		User: &UserInfo{
			ID:       user.ID,
			AppleID:  user.AppleID,
			Email:    user.Email,
			FullName: user.FullName,
		},
		ExpiresIn: int64(time.Until(newExpiresAt).Seconds()),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// HandleLogout ログアウトを処理します
func (h *AuthHandler) HandleLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

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

	ctx := r.Context()

	// セッションを削除
	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		// セッションが存在しない場合も成功として扱う
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Logged out successfully"})
}

// generateAccessToken はアクセストークンを生成します
func (h *AuthHandler) generateAccessToken(userID uuid.UUID) (string, time.Time, error) {
	expiresAt := time.Now().Add(24 * time.Hour) // 24時間有効

	claims := jwt.MapClaims{
		"user_id":    userID.String(),
		"exp":        expiresAt.Unix(),
		"iat":        time.Now().Unix(),
		"token_type": "access",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(h.jwtSecret))
	if err != nil {
		return "", time.Time{}, fmt.Errorf("failed to sign token: %w", err)
	}

	return tokenString, expiresAt, nil
}
