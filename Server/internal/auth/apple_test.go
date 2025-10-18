package auth

import (
	"testing"
	"time"
)

func TestAppleAuthService_ValidateClaims(t *testing.T) {
	service := NewAppleAuthService("com.test.app", "TEAM123", "KEY123")

	tests := []struct {
		name    string
		claims  *AppleIDTokenClaims
		wantErr bool
	}{
		{
			name: "valid claims",
			claims: &AppleIDTokenClaims{
				Iss: "https://appleid.apple.com",
				Aud: "com.test.app",
				Exp: time.Now().Add(time.Hour).Unix(),
				Iat: time.Now().Add(-time.Minute).Unix(),
				Sub: "user123",
			},
			wantErr: false,
		},
		{
			name: "invalid issuer",
			claims: &AppleIDTokenClaims{
				Iss: "https://invalid.com",
				Aud: "com.test.app",
				Exp: time.Now().Add(time.Hour).Unix(),
				Iat: time.Now().Add(-time.Minute).Unix(),
				Sub: "user123",
			},
			wantErr: true,
		},
		{
			name: "invalid audience",
			claims: &AppleIDTokenClaims{
				Iss: "https://appleid.apple.com",
				Aud: "com.wrong.app",
				Exp: time.Now().Add(time.Hour).Unix(),
				Iat: time.Now().Add(-time.Minute).Unix(),
				Sub: "user123",
			},
			wantErr: true,
		},
		{
			name: "expired token",
			claims: &AppleIDTokenClaims{
				Iss: "https://appleid.apple.com",
				Aud: "com.test.app",
				Exp: time.Now().Add(-time.Hour).Unix(),
				Iat: time.Now().Add(-2 * time.Hour).Unix(),
				Sub: "user123",
			},
			wantErr: true,
		},
		{
			name: "empty subject",
			claims: &AppleIDTokenClaims{
				Iss: "https://appleid.apple.com",
				Aud: "com.test.app",
				Exp: time.Now().Add(time.Hour).Unix(),
				Iat: time.Now().Add(-time.Minute).Unix(),
				Sub: "",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := service.validateClaims(tt.claims)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateClaims() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestAppleAuthService_ParsePublicKey(t *testing.T) {
	service := NewAppleAuthService("com.test.app", "TEAM123", "KEY123")

	// テスト用のApple公開鍵（無効なBase64値）
	key := ApplePublicKey{
		Kty: "RSA",
		Kid: "test-key-id",
		Use: "sig",
		Alg: "RS256",
		N:   "invalid-base64-value-with-special-chars!@#",
		E:   "AQAB",
	}

	// 無効なキーでパースを試行
	_, err := service.parsePublicKey(key)
	if err == nil {
		t.Error("Expected error for invalid key, got nil")
	}
}

func TestAppleAuthService_NewAppleAuthService(t *testing.T) {
	clientID := "com.test.app"
	teamID := "TEAM123"
	keyID := "KEY123"

	service := NewAppleAuthService(clientID, teamID, keyID)

	if service.clientID != clientID {
		t.Errorf("Expected clientID %s, got %s", clientID, service.clientID)
	}

	if service.teamID != teamID {
		t.Errorf("Expected teamID %s, got %s", teamID, service.teamID)
	}

	if service.keyID != keyID {
		t.Errorf("Expected keyID %s, got %s", keyID, service.keyID)
	}

	if service.httpClient == nil {
		t.Error("Expected httpClient to be initialized")
	}

	if service.publicKeys == nil {
		t.Error("Expected publicKeys map to be initialized")
	}
}
