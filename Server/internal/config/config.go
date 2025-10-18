package config

import (
	"fmt"
	"os"
	"strings"
)

// Config はアプリケーションの設定を管理します
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Auth     AuthConfig
	CORS     CORSConfig
}

// ServerConfig はサーバー設定です
type ServerConfig struct {
	Port string
}

// DatabaseConfig はデータベース設定です
type DatabaseConfig struct {
	URL string
}

// AuthConfig は認証設定です
type AuthConfig struct {
	JWTSecret string
}

// CORSConfig はCORS設定です
type CORSConfig struct {
	AllowedOrigins []string
}

// Load は環境変数から設定を読み込みます
func Load() (*Config, error) {
	config := &Config{
		Server: ServerConfig{
			Port: getEnv("PORT", "8080"),
		},
		Database: DatabaseConfig{
			URL: getEnv("DATABASE_URL", ""),
		},
		Auth: AuthConfig{
			JWTSecret: getEnv("JWT_SECRET", ""),
		},
		CORS: CORSConfig{
			AllowedOrigins: getEnvSlice("CORS_ALLOWED_ORIGINS", []string{"*"}),
		},
	}

	// 必須設定の検証
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return config, nil
}

// Validate は設定の妥当性を検証します
func (c *Config) Validate() error {
	if c.Auth.JWTSecret == "" {
		return fmt.Errorf("JWT_SECRET is required")
	}

	return nil
}

// getEnv は環境変数を取得し、デフォルト値を返します
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvSlice は環境変数をカンマ区切りのスライスとして取得します
func getEnvSlice(key string, defaultValue []string) []string {
	if value := os.Getenv(key); value != "" {
		return strings.Split(value, ",")
	}
	return defaultValue
}
