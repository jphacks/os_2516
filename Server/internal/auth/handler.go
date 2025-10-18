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
	"golang.org/x/crypto/bcrypt"
)

// PlayerRepository はプレイヤーリポジトリのインターフェースです
type PlayerRepository interface {
	CreatePlayer(ctx context.Context, player *entities.Player) error
	GetPlayerByUserID(ctx context.Context, userID uuid.UUID) (*entities.Player, error)
}

// AuthHandler は認証関連のHTTPハンドラーです
type AuthHandler struct {
	userRepo    UserRepository
	playerRepo  PlayerRepository
	sessionRepo SessionRepository
	jwtSecret   string
}

// UserRepository はユーザーリポジトリのインターフェースです
type UserRepository interface {
	CreateUser(ctx context.Context, user *entities.User) error
	GetUserByEmail(ctx context.Context, email string) (*entities.User, error)
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
func NewAuthHandler(userRepo UserRepository, playerRepo PlayerRepository, sessionRepo SessionRepository, jwtSecret string) *AuthHandler {
	return &AuthHandler{
		userRepo:    userRepo,
		playerRepo:  playerRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   jwtSecret,
	}
}

// SignUpRequest はユーザー登録リクエストです
type SignUpRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	FullName string `json:"full_name"`
}

// SignInRequest はサインインリクエストです
type SignInRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// SignInResponse はサインインレスポンスです
type SignInResponse struct {
	AccessToken string    `json:"access_token"`
	User        *UserInfo `json:"user"`
	ExpiresIn   int64     `json:"expires_in"`
}

// UserInfo はレスポンスに含めるユーザー情報です
type UserInfo struct {
	ID       uuid.UUID `json:"id"`
	Email    string    `json:"email"`
	FullName string    `json:"full_name"`
}

// HandleSignUp はユーザー登録を処理します
func (h *AuthHandler) HandleSignUp(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if !h.ensureDependencies(w) {
		return
	}

	var req SignUpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	email := normalizeEmail(req.Email)
	if email == "" || len(req.Password) < 8 {
		http.Error(w, "Invalid email or password", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	if _, err := h.userRepo.GetUserByEmail(ctx, email); err == nil {
		http.Error(w, "User already exists", http.StatusConflict)
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "Failed to process password", http.StatusInternalServerError)
		return
	}

	user := entities.NewUser(email, string(hashedPassword), strings.TrimSpace(req.FullName))
	if err := h.userRepo.CreateUser(ctx, user); err != nil {
		http.Error(w, "Failed to create user", http.StatusInternalServerError)
		return
	}

	player := entities.NewPlayer(&user.ID, user.FullName)
	if err := h.playerRepo.CreatePlayer(ctx, player); err != nil {
		http.Error(w, "Failed to create player", http.StatusInternalServerError)
		return
	}

	accessToken, expiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate access token", http.StatusInternalServerError)
		return
	}

	session := entities.NewSession(user.ID, accessToken, expiresAt)
	if err := h.sessionRepo.CreateSession(ctx, session); err != nil {
		http.Error(w, "Failed to create session", http.StatusInternalServerError)
		return
	}

	response := SignInResponse{
		AccessToken: accessToken,
		User: &UserInfo{
			ID:       user.ID,
			Email:    user.Email,
			FullName: user.FullName,
		},
		ExpiresIn: int64(time.Until(expiresAt).Seconds()),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(response)
}

// HandleSignIn はメール・パスワードによるサインインを処理します
func (h *AuthHandler) HandleSignIn(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if !h.ensureDependencies(w) {
		return
	}

	var req SignInRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	email := normalizeEmail(req.Email)
	if email == "" || req.Password == "" {
		http.Error(w, "Invalid email or password", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	user, err := h.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		http.Error(w, "Invalid email or password", http.StatusUnauthorized)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		http.Error(w, "Invalid email or password", http.StatusUnauthorized)
		return
	}

	accessToken, expiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate access token", http.StatusInternalServerError)
		return
	}

	session := entities.NewSession(user.ID, accessToken, expiresAt)
	if err := h.sessionRepo.CreateSession(ctx, session); err != nil {
		http.Error(w, "Failed to create session", http.StatusInternalServerError)
		return
	}

	response := SignInResponse{
		AccessToken: accessToken,
		User: &UserInfo{
			ID:       user.ID,
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

	if !h.ensureDependencies(w) {
		return
	}

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

	session, err := h.sessionRepo.GetSessionByToken(ctx, token)
	if err != nil {
		http.Error(w, "Invalid session", http.StatusUnauthorized)
		return
	}

	if session.IsExpired() {
		http.Error(w, "Session expired", http.StatusUnauthorized)
		return
	}

	user, err := h.userRepo.GetUserByID(ctx, session.UserID)
	if err != nil {
		http.Error(w, "User not found", http.StatusUnauthorized)
		return
	}

	newAccessToken, newExpiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate new access token", http.StatusInternalServerError)
		return
	}

	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		// セッションが見つからなくても致命的ではないので処理を続行
	}

	newSession := entities.NewSession(user.ID, newAccessToken, newExpiresAt)
	if err := h.sessionRepo.CreateSession(ctx, newSession); err != nil {
		http.Error(w, "Failed to create new session", http.StatusInternalServerError)
		return
	}

	response := SignInResponse{
		AccessToken: newAccessToken,
		User: &UserInfo{
			ID:       user.ID,
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

	if !h.ensureDependencies(w) {
		return
	}

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

	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		// セッションが存在しない場合も成功として扱う
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Logged out successfully"})
}

// generateAccessToken はアクセストークンを生成します
func (h *AuthHandler) generateAccessToken(userID uuid.UUID) (string, time.Time, error) {
	expiresAt := time.Now().Add(24 * time.Hour)

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

func normalizeEmail(email string) string {
	return strings.TrimSpace(strings.ToLower(email))
}

func (h *AuthHandler) ensureDependencies(w http.ResponseWriter) bool {
	if h.userRepo == nil || h.playerRepo == nil || h.sessionRepo == nil {
		http.Error(w, "Authentication service unavailable", http.StatusServiceUnavailable)
		return false
	}
	return true
}
