# Server サービス概要

Go 製の最小構成 REST API です。`/health` と `/supabase/health` エンドポイントを提供し、Cloud Run 上で稼働することを前提にしています。

## 必要な環境変数
`.env.example` を参考に `.env` を作成してください。

- `PORT`: ローカル起動時に使用するポート（Cloud Run では自動設定）
- `SUPABASE_DB_URL`: Supabase Postgres への接続文字列（Secret Manager 連携を推奨）

## ローカル開発
```bash
cd Server
GOCACHE=$(pwd)/.gocache go run cmd/server/main.go
```
`http://localhost:8080/health` で疎通確認、Supabase 連携確認は `/supabase/health` を参照してください。

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

