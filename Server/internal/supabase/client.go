package supabase

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Client は Supabase Postgres への最小限の操作を定義します。
type Client interface {
	Ready() bool
	Health(ctx context.Context) (*HealthResponse, error)
	Close()
}

// HealthResponse はヘルスチェック結果を保持します。
type HealthResponse struct {
	Status string `json:"status"`
}

type pgClient struct {
	pool *pgxpool.Pool
}

type noopClient struct {
	err error
}

// NewClient は Supabase Postgres への接続プールを構築します。
func NewClient(ctx context.Context, connString string) (Client, error) {
	trimmed := strings.TrimSpace(connString)
	if trimmed == "" {
		return NewNoopClient(errors.New("empty connection string")), errors.New("empty connection string")
	}

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, trimmed)
	if err != nil {
		return NewNoopClient(fmt.Errorf("create supabase pool: %w", err)), fmt.Errorf("create supabase pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return NewNoopClient(fmt.Errorf("ping supabase: %w", err)), fmt.Errorf("ping supabase: %w", err)
	}

	return &pgClient{pool: pool}, nil
}

// NewClientFromEnv は環境変数からクライアントを生成します。
// SUPABASE_DB_URL が不足している場合は noop クライアントとエラーを返します。
func NewClientFromEnv(ctx context.Context) (Client, error) {
	connString := os.Getenv("SUPABASE_DB_URL")

	if strings.TrimSpace(connString) == "" {
		err := errors.New("missing environment variable: SUPABASE_DB_URL")
		return NewNoopClient(err), err
	}

	return NewClient(ctx, connString)
}

// NewNoopClient は設定不足時に使用するダミークライアントを返します。
func NewNoopClient(err error) Client {
	if err == nil {
		err = errors.New("supabase client not configured")
	}
	return &noopClient{err: err}
}

// Ready は Supabase への実接続が構成済みかを返します。
func (c *pgClient) Ready() bool {
	return c.pool != nil
}

// Health は Supabase Postgres に対して Ping を行います。
func (c *pgClient) Health(ctx context.Context) (*HealthResponse, error) {
	if c.pool == nil {
		return nil, errors.New("supabase pool not initialised")
	}

	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()

	if err := c.pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("supabase ping failed: %w", err)
	}

	return &HealthResponse{Status: "ok"}, nil
}

// Close は接続プールを解放します。
func (c *pgClient) Close() {
	if c.pool != nil {
		c.pool.Close()
	}
}

// Ready は noop クライアントでは常に false を返します。
func (c *noopClient) Ready() bool {
	return false
}

// Health は noop クライアントでは設定不足エラーを返します。
func (c *noopClient) Health(context.Context) (*HealthResponse, error) {
	return nil, c.err
}

// Close は noop クライアントでは何もしません。
func (c *noopClient) Close() {}
