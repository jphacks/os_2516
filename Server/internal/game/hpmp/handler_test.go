package hpmp

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"server/internal/auth"
	"server/internal/domain/entities"

	"github.com/google/uuid"
)

// createTestPlayer はテスト用のプレイヤーを作成します
func createTestPlayer(userID uuid.UUID, hp, mp int) *entities.Player {
	return &entities.Player{
		ID:          uuid.New(),
		UserID:      &userID,
		DisplayName: "Test Player",
		HP:          hp,
		MP:          mp,
		Rank:        0,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
}

func TestHPMPHandler_HandleGetHP(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 150, 200)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	req := httptest.NewRequest(http.MethodGet, "/api/hp", nil)
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))
	w := httptest.NewRecorder()

	handler.HandleGetHP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, w.Code)
	}

	var response HPResponse
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response.HP != 150 {
		t.Errorf("Expected HP 150, got %d", response.HP)
	}
}

func TestHPMPHandler_HandleGetMP(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 150, 200)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	req := httptest.NewRequest(http.MethodGet, "/api/mp", nil)
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))
	w := httptest.NewRecorder()

	handler.HandleGetMP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, w.Code)
	}

	var response MPResponse
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response.MP != 200 {
		t.Errorf("Expected MP 200, got %d", response.MP)
	}
}

func TestHPMPHandler_HandleUpdateHP(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 100, 100)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	// リクエストボディを作成
	updateReq := UpdateHPRequest{HP: 250}
	reqBody, _ := json.Marshal(updateReq)

	// リクエストを作成
	req := httptest.NewRequest(http.MethodPut, "/api/hp/update", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))

	// レスポンスレコーダーを作成
	w := httptest.NewRecorder()

	// ハンドラーを実行
	handler.HandleUpdateHP(w, req)

	// レスポンスを検証
	if w.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, w.Code)
	}

	var response HPResponse
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response.HP != 250 {
		t.Errorf("Expected HP 250, got %d", response.HP)
	}

	// データベースの更新を確認
	updatedPlayer, err := mockRepo.GetPlayerByUserID(context.Background(), userID)
	if err != nil {
		t.Fatalf("Failed to get updated player: %v", err)
	}

	if updatedPlayer.HP != 250 {
		t.Errorf("Expected updated HP 250, got %d", updatedPlayer.HP)
	}
}

func TestHPMPHandler_HandleUpdateMP(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 100, 100)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	// リクエストボディを作成
	updateReq := UpdateMPRequest{MP: 300}
	reqBody, _ := json.Marshal(updateReq)

	// リクエストを作成
	req := httptest.NewRequest(http.MethodPut, "/api/mp/update", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))

	// レスポンスレコーダーを作成
	w := httptest.NewRecorder()

	// ハンドラーを実行
	handler.HandleUpdateMP(w, req)

	// レスポンスを検証
	if w.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, w.Code)
	}

	var response MPResponse
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response.MP != 300 {
		t.Errorf("Expected MP 300, got %d", response.MP)
	}

	// データベースの更新を確認
	updatedPlayer, err := mockRepo.GetPlayerByUserID(context.Background(), userID)
	if err != nil {
		t.Fatalf("Failed to get updated player: %v", err)
	}

	if updatedPlayer.MP != 300 {
		t.Errorf("Expected updated MP 300, got %d", updatedPlayer.MP)
	}
}

func TestHPMPHandler_HandleUpdateHP_Validation(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 100, 100)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	testCases := []struct {
		name         string
		hp           int
		expectedCode int
	}{
		{"Valid HP", 500, http.StatusOK},
		{"HP too high", 1001, http.StatusBadRequest},
		{"HP negative", -1, http.StatusBadRequest},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// リクエストボディを作成
			updateReq := UpdateHPRequest{HP: tc.hp}
			reqBody, _ := json.Marshal(updateReq)

			// リクエストを作成
			req := httptest.NewRequest(http.MethodPut, "/api/hp/update", bytes.NewBuffer(reqBody))
			req.Header.Set("Content-Type", "application/json")
			req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))

			// レスポンスレコーダーを作成
			w := httptest.NewRecorder()

			// ハンドラーを実行
			handler.HandleUpdateHP(w, req)

			// レスポンスを検証
			if w.Code != tc.expectedCode {
				t.Errorf("Expected status code %d, got %d", tc.expectedCode, w.Code)
			}
		})
	}
}

func TestHPMPHandler_HandleUpdateMP_Validation(t *testing.T) {
	userID := uuid.New()
	player := createTestPlayer(userID, 100, 100)
	mockRepo := auth.NewMockPlayerRepository()
	mockRepo.CreatePlayer(context.Background(), player)
	handler := NewHPMPHandler(mockRepo)

	testCases := []struct {
		name         string
		mp           int
		expectedCode int
	}{
		{"Valid MP", 500, http.StatusOK},
		{"MP too high", 1001, http.StatusBadRequest},
		{"MP negative", -1, http.StatusBadRequest},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// リクエストボディを作成
			updateReq := UpdateMPRequest{MP: tc.mp}
			reqBody, _ := json.Marshal(updateReq)

			// リクエストを作成
			req := httptest.NewRequest(http.MethodPut, "/api/mp/update", bytes.NewBuffer(reqBody))
			req.Header.Set("Content-Type", "application/json")
			req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))

			// レスポンスレコーダーを作成
			w := httptest.NewRecorder()

			// ハンドラーを実行
			handler.HandleUpdateMP(w, req)

			// レスポンスを検証
			if w.Code != tc.expectedCode {
				t.Errorf("Expected status code %d, got %d", tc.expectedCode, w.Code)
			}
		})
	}
}
