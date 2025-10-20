# Server サービス概要

Go 製のREST API です。メールアドレスとパスワードによる認証機能とリアルタイム格闘ゲームのバックエンド機能を提供し、Cloud Run 上で稼働することを前提にしています。

## 機能

### 認証機能
- メールアドレス／パスワード認証
- JWT トークンベースのセッション管理
- 認証ミドルウェアによるエンドポイント保護

### API エンドポイント
- `/health` - ヘルスチェック
- `/supabase/health` - Supabase接続確認
- `/auth/signup` - 新規登録
- `/auth/signin` - サインイン

- `/auth/refresh` - トークンリフレッシュ
- `/auth/logout` - ログアウト
- `/api/protected` - 認証が必要なエンドポイント（例）

## 必要な環境変数
`.env.example` を参考に `.env` を作成してください。

### 基本設定
- `PORT`: ローカル起動時に使用するポート（Cloud Run では自動設定）
- `DATABASE_URL`: PostgreSQL への接続文字列（設定がなければ `SUPABASE_DB_URL` を自動的に利用）
- `SUPABASE_DB_URL`: Supabase Postgres への接続文字列（Secret Manager 連携を推奨）

### 認証設定
- `JWT_SECRET`: JWT署名用の秘密鍵

### セキュリティ設定
- `CORS_ALLOWED_ORIGINS`: 許可するオリジン（カンマ区切り）

## データベースセットアップ

認証機能を使用するには、データベースのマイグレーションを実行してください：

```bash
cd Server
# PostgreSQLに接続してマイグレーションを実行
psql $DATABASE_URL -f migrations/001_create_auth_tables.sql
```

## ローカル開発
```bash
cd Server
# 環境変数を設定
export JWT_SECRET="your-secret-key"
export DATABASE_URL="postgres://username:password@localhost:5432/database_name"

# サーバーを起動
GOCACHE=$(pwd)/.gocache go run cmd/server/main.go
```

`http://localhost:8080/health` で疎通確認、Supabase 連携確認は `/supabase/health` を参照してください。

## テスト実行
```bash
cd Server
go test ./...
```

## Docker ビルド
```bash
cd Server
docker build -t os2516-server:local .
docker run --rm -p 8080:8080 \
  -e SUPABASE_DB_URL=$SUPABASE_DB_URL \
  os2516-server:local

# ヘルスチェック
curl http://localhost:8080/health
```

## Cloud Run デプロイ (GitHub Actions)
`GCP_PROJECT`, `GCP_REGION`, `CLOUD_RUN_SERVICE`, `GCP_SA_KEY`, `SUPABASE_DB_URL` を GitHub Secrets に登録すると、`deploy-cloudrun` ワークフローがトリガーされた際に Cloud Run へ自動デプロイされます。デプロイ後、ワークフローの `Verify health endpoint` ステップが `/health` を自動検証します。
