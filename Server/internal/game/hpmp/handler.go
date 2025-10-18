package hpmp

import (
	"encoding/json"
	"fmt"
	"net/http"

	"server/internal/auth"
	"server/internal/domain/entities"
)

// HPMPHandler はHP/MP関連のHTTPハンドラーです
type HPMPHandler struct {
	userRepo auth.UserRepository
}

// NewHPMPHandler は新しいHP/MPハンドラーを作成します
func NewHPMPHandler(userRepo auth.UserRepository) *HPMPHandler {
	return &HPMPHandler{
		userRepo: userRepo,
	}
}

// HPResponse HP取得レスポンス
type HPResponse struct {
	HP int `json:"hp"`
}

// MPResponse MP取得レスポンス
type MPResponse struct {
	MP int `json:"mp"`
}

// UpdateHPRequest HP更新リクエスト
type UpdateHPRequest struct {
	HP int `json:"hp"`
}

// UpdateMPRequest MP更新リクエスト
type UpdateMPRequest struct {
	MP int `json:"mp"`
}

// HandleGetHP はログインしているユーザーのHPを取得します
func (h *HPMPHandler) HandleGetHP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	user, err := h.getCurrentUser(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	response := HPResponse{HP: user.HP}
	h.respondJSON(w, response)
}

// HandleGetMP はログインしているユーザーのMPを取得します
func (h *HPMPHandler) HandleGetMP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	user, err := h.getCurrentUser(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	response := MPResponse{MP: user.MP}
	h.respondJSON(w, response)
}

// HandleUpdateHP はログインしているユーザーのHPを更新します
func (h *HPMPHandler) HandleUpdateHP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 認証ミドルウェアからユーザーIDを取得
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "User ID not found in context", http.StatusInternalServerError)
		return
	}

	var req UpdateHPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// HP値のバリデーション
	if req.HP < 0 || req.HP > 1000 {
		http.Error(w, "HP must be between 0 and 1000", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// HPを更新
	if err := h.userRepo.UpdateUserHP(ctx, userID, req.HP); err != nil {
		http.Error(w, "Failed to update HP", http.StatusInternalServerError)
		return
	}

	// レスポンスを返す
	response := HPResponse(req)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// HandleUpdateMP はログインしているユーザーのMPを更新します
func (h *HPMPHandler) HandleUpdateMP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 認証ミドルウェアからユーザーIDを取得
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "User ID not found in context", http.StatusInternalServerError)
		return
	}

	var req UpdateMPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// MP値のバリデーション
	if req.MP < 0 || req.MP > 1000 {
		http.Error(w, "MP must be between 0 and 1000", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// MPを更新
	if err := h.userRepo.UpdateUserMP(ctx, userID, req.MP); err != nil {
		http.Error(w, "Failed to update MP", http.StatusInternalServerError)
		return
	}

	// レスポンスを返す
	response := MPResponse(req)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// getCurrentUser は現在ログインしているユーザーを取得します
func (h *HPMPHandler) getCurrentUser(r *http.Request) (*entities.User, error) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		return nil, fmt.Errorf("user ID not found in context")
	}

	user, err := h.userRepo.GetUserByID(r.Context(), userID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}

	return user, nil
}

// respondJSON はJSONレスポンスを返します
func (h *HPMPHandler) respondJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}
