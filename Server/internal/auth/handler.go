package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
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
		h.respondError(w, r, http.StatusMethodNotAllowed, "Method not allowed", nil)
		return
	}

	if !h.ensureDependencies(w, r) {
		return
	}

	var req SignUpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, r, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	email := normalizeEmail(req.Email)
	if email == "" || len(req.Password) < 8 {
		h.respondError(w, r, http.StatusBadRequest, "Invalid email or password", fmt.Errorf("email=%q length=%d", email, len(req.Password)))
		return
	}

	ctx := r.Context()

	if _, err := h.userRepo.GetUserByEmail(ctx, email); err == nil {
		h.respondError(w, r, http.StatusConflict, "User already exists", fmt.Errorf("email=%s", email))
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to process password", err)
		return
	}

	user := entities.NewUser(email, string(hashedPassword), strings.TrimSpace(req.FullName))
	if err := h.userRepo.CreateUser(ctx, user); err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to create user", err)
		return
	}

	player := entities.NewPlayer(&user.ID, user.FullName)
	if err := h.playerRepo.CreatePlayer(ctx, player); err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to create player", err)
		return
	}

	accessToken, expiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to generate access token", err)
		return
	}

	session := entities.NewSession(user.ID, accessToken, expiresAt)
	if err := h.sessionRepo.CreateSession(ctx, session); err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to create session", err)
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
		h.respondError(w, r, http.StatusMethodNotAllowed, "Method not allowed", nil)
		return
	}

	if !h.ensureDependencies(w, r) {
		return
	}

	var req SignInRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, r, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	email := normalizeEmail(req.Email)
	if email == "" || req.Password == "" {
		h.respondError(w, r, http.StatusBadRequest, "Invalid email or password", fmt.Errorf("email empty? %t password length=%d", email == "", len(req.Password)))
		return
	}

	ctx := r.Context()

	user, err := h.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		h.respondError(w, r, http.StatusUnauthorized, "Invalid email or password", err)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		h.respondError(w, r, http.StatusUnauthorized, "Invalid email or password", err)
		return
	}

	accessToken, expiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to generate access token", err)
		return
	}

	session := entities.NewSession(user.ID, accessToken, expiresAt)
	if err := h.sessionRepo.CreateSession(ctx, session); err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to create session", err)
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
		h.respondError(w, r, http.StatusMethodNotAllowed, "Method not allowed", nil)
		return
	}

	if !h.ensureDependencies(w, r) {
		return
	}

	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		h.respondError(w, r, http.StatusUnauthorized, "Authorization header required", nil)
		return
	}

	token := strings.TrimPrefix(authHeader, "Bearer ")
	if token == authHeader {
		h.respondError(w, r, http.StatusUnauthorized, "Invalid authorization header format", fmt.Errorf("auth header=%s", authHeader))
		return
	}

	ctx := r.Context()

	session, err := h.sessionRepo.GetSessionByToken(ctx, token)
	if err != nil {
		h.respondError(w, r, http.StatusUnauthorized, "Invalid session", err)
		return
	}

	if session.IsExpired() {
		h.respondError(w, r, http.StatusUnauthorized, "Session expired", fmt.Errorf("token=%s", token))
		return
	}

	user, err := h.userRepo.GetUserByID(ctx, session.UserID)
	if err != nil {
		h.respondError(w, r, http.StatusUnauthorized, "User not found", err)
		return
	}

	newAccessToken, newExpiresAt, err := h.generateAccessToken(user.ID)
	if err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to generate new access token", err)
		return
	}

	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		// セッションが見つからなくても致命的ではないので処理を続行
	}

	newSession := entities.NewSession(user.ID, newAccessToken, newExpiresAt)
	if err := h.sessionRepo.CreateSession(ctx, newSession); err != nil {
		h.respondError(w, r, http.StatusInternalServerError, "Failed to create new session", err)
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
		h.respondError(w, r, http.StatusMethodNotAllowed, "Method not allowed", nil)
		return
	}

	if !h.ensureDependencies(w, r) {
		return
	}

	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		h.respondError(w, r, http.StatusUnauthorized, "Authorization header required", nil)
		return
	}

	token := strings.TrimPrefix(authHeader, "Bearer ")
	if token == authHeader {
		h.respondError(w, r, http.StatusUnauthorized, "Invalid authorization header format", fmt.Errorf("auth header=%s", authHeader))
		return
	}

	ctx := r.Context()

	if err := h.sessionRepo.DeleteSession(ctx, token); err != nil {
		log.Printf("auth: failed to delete session token=%s: %v", token, err)
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

func (h *AuthHandler) ensureDependencies(w http.ResponseWriter, r *http.Request) bool {
	if h.userRepo == nil || h.playerRepo == nil || h.sessionRepo == nil {
		h.respondError(w, r, http.StatusServiceUnavailable, "Authentication service unavailable", fmt.Errorf("userRepo nil=%t playerRepo nil=%t sessionRepo nil=%t", h.userRepo == nil, h.playerRepo == nil, h.sessionRepo == nil))
		return false
	}
	return true
}

func (h *AuthHandler) respondError(w http.ResponseWriter, r *http.Request, status int, clientMessage string, err error) {
	log.Printf("auth: %s %s -> status=%d message=%s error=%v", r.Method, r.URL.Path, status, clientMessage, err)
	http.Error(w, clientMessage, status)
}
