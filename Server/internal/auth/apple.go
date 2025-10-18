package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// AppleIDTokenClaims Apple ID Tokenのクレーム構造体
type AppleIDTokenClaims struct {
	Iss            string `json:"iss"`                        // 発行者 (Apple)
	Aud            string `json:"aud"`                        // 対象者 (アプリのBundle ID)
	Exp            int64  `json:"exp"`                        // 有効期限
	Iat            int64  `json:"iat"`                        // 発行時刻
	Sub            string `json:"sub"`                        // ユーザー識別子
	Email          string `json:"email"`                      // メールアドレス
	EmailVerified  string `json:"email_verified"`             // メール検証済み
	IsPrivateEmail string `json:"is_private_email,omitempty"` // プライベートメール
	jwt.RegisteredClaims
}

// ApplePublicKey Apple公開鍵の構造体
type ApplePublicKey struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// ApplePublicKeysResponse Apple公開鍵取得APIのレスポンス
type ApplePublicKeysResponse struct {
	Keys []ApplePublicKey `json:"keys"`
}

// AppleAuthService Apple認証サービス
type AppleAuthService struct {
	clientID     string
	teamID       string
	keyID        string
	httpClient   *http.Client
	publicKeys   map[string]*rsa.PublicKey
	lastFetch    time.Time
	keysCacheTTL time.Duration
}

// NewAppleAuthService は新しいApple認証サービスを作成します
func NewAppleAuthService(clientID, teamID, keyID string) *AppleAuthService {
	return &AppleAuthService{
		clientID:     clientID,
		teamID:       teamID,
		keyID:        keyID,
		httpClient:   &http.Client{Timeout: 10 * time.Second},
		publicKeys:   make(map[string]*rsa.PublicKey),
		keysCacheTTL: 24 * time.Hour, // 公開鍵は24時間キャッシュ
	}
}

// VerifyIDToken Apple ID Tokenを検証します
func (s *AppleAuthService) VerifyIDToken(ctx context.Context, idToken string) (*AppleIDTokenClaims, error) {
	// 1. JWTトークンをパース
	token, err := jwt.ParseWithClaims(idToken, &AppleIDTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		// アルゴリズムの確認
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		// キーIDの取得
		kid, ok := token.Header["kid"].(string)
		if !ok {
			return nil, fmt.Errorf("kid not found in token header")
		}

		// 公開鍵の取得
		publicKey, err := s.getPublicKey(ctx, kid)
		if err != nil {
			return nil, fmt.Errorf("failed to get public key: %w", err)
		}

		return publicKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	// 2. クレームの取得
	claims, ok := token.Claims.(*AppleIDTokenClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	// 3. 基本的な検証
	if err := s.validateClaims(claims); err != nil {
		return nil, fmt.Errorf("claim validation failed: %w", err)
	}

	return claims, nil
}

// getPublicKey は指定されたキーIDの公開鍵を取得します
func (s *AppleAuthService) getPublicKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	// キャッシュから取得を試行
	if publicKey, exists := s.publicKeys[kid]; exists && time.Since(s.lastFetch) < s.keysCacheTTL {
		return publicKey, nil
	}

	// キャッシュが無効または存在しない場合、Appleから取得
	if err := s.fetchPublicKeys(ctx); err != nil {
		return nil, fmt.Errorf("failed to fetch public keys: %w", err)
	}

	// 再度キャッシュから取得
	publicKey, exists := s.publicKeys[kid]
	if !exists {
		return nil, fmt.Errorf("public key not found for kid: %s", kid)
	}

	return publicKey, nil
}

// fetchPublicKeys はAppleから公開鍵を取得します
func (s *AppleAuthService) fetchPublicKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, "GET", "https://appleid.apple.com/auth/keys", nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch public keys: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	var keysResponse ApplePublicKeysResponse
	if err := json.Unmarshal(body, &keysResponse); err != nil {
		return fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// 公開鍵をパースしてキャッシュに保存
	newKeys := make(map[string]*rsa.PublicKey)
	for _, key := range keysResponse.Keys {
		publicKey, err := s.parsePublicKey(key)
		if err != nil {
			continue // パースに失敗したキーはスキップ
		}
		newKeys[key.Kid] = publicKey
	}

	s.publicKeys = newKeys
	s.lastFetch = time.Now()

	return nil
}

// parsePublicKey はApple公開鍵をRSA公開鍵に変換します
func (s *AppleAuthService) parsePublicKey(key ApplePublicKey) (*rsa.PublicKey, error) {
	// Base64URLデコード
	nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode n: %w", err)
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode e: %w", err)
	}

	// big.Intに変換
	n := new(big.Int).SetBytes(nBytes)
	e := new(big.Int).SetBytes(eBytes)

	// RSA公開鍵を作成
	publicKey := &rsa.PublicKey{
		N: n,
		E: int(e.Int64()),
	}

	return publicKey, nil
}

// validateClaims はトークンのクレームを検証します
func (s *AppleAuthService) validateClaims(claims *AppleIDTokenClaims) error {
	// 発行者の確認
	if claims.Iss != "https://appleid.apple.com" {
		return fmt.Errorf("invalid issuer: %s", claims.Iss)
	}

	// 対象者の確認
	if claims.Aud != s.clientID {
		return fmt.Errorf("invalid audience: %s", claims.Aud)
	}

	// 有効期限の確認
	if time.Now().Unix() > claims.Exp {
		return fmt.Errorf("token expired")
	}

	// 発行時刻の確認（未来の時刻でないか）
	if time.Now().Unix() < claims.Iat {
		return fmt.Errorf("token issued in the future")
	}

	// ユーザー識別子の確認
	if claims.Sub == "" {
		return fmt.Errorf("subject is empty")
	}

	return nil
}
