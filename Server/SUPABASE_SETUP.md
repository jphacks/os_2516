# Supabase連携セットアップ手順

## 概要
Real Fighting Game APIのSupabase連携を設定するための手順書です。

## 前提条件
- Supabaseアカウント
- PostgreSQLデータベースへのアクセス権限
- Go 1.21以上

## 1. Supabaseプロジェクトの作成

1. [Supabase Dashboard](https://supabase.com/dashboard)にログイン
2. 「New Project」をクリック
3. プロジェクト名を入力（例: `real-fighting-game`）
4. データベースパスワードを設定
5. リージョンを選択（推奨: `Asia Northeast (Tokyo)`）
6. 「Create new project」をクリック

## 2. データベース接続情報の取得

1. プロジェクトダッシュボードで「Settings」→「Database」を選択
2. 「Connection string」セクションで「URI」をコピー
3. 以下の形式で接続文字列を取得：
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres
   ```

## 3. 環境変数の設定

### 3.1 環境変数ファイルの作成
```bash
cd Server
cp env.example .env
```

### 3.2 環境変数の設定
`.env`ファイルを編集して以下の値を設定：

```env
# データベース接続
SUPABASE_DB_URL=postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres

# JWT設定
JWT_SECRET=your-super-secret-jwt-key-here

# CORS設定
CORS_ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com
```

## 4. データベースマイグレーションの実行

### 4.1 マイグレーションファイルの確認
以下のマイグレーションファイルが存在することを確認：
- `migrations/001_create_auth_tables.sql`
- `migrations/002_create_players_table.sql`

### 4.2 マイグレーションの実行
SupabaseのSQL Editorまたはpsqlを使用してマイグレーションを実行：

```bash
# psqlを使用する場合
psql "postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" -f migrations/001_create_auth_tables.sql
psql "postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" -f migrations/002_create_players_table.sql
```

または、Supabase DashboardのSQL Editorで各ファイルの内容を実行。

## 5. メール・パスワード認証設定

外部プロバイダ連携は不要です。ユーザー登録時にメールアドレスとパスワードをAPIへ送信するだけで利用できます。
フロントエンドでは `/auth/signup` と `/auth/signin` のエンドポイントに対してJSONをPOSTする実装を用意してください。

## 6. サーバーの起動

### 6.1 依存関係のインストール
```bash
cd Server
go mod tidy
```

### 6.2 サーバーの起動
```bash
go run cmd/server/main.go
```

### 6.3 動作確認
```bash
# ヘルスチェック
curl http://localhost:8080/health

# Supabase接続確認
curl http://localhost:8080/supabase/health
```

## 7. APIテスト

### 7.1 サインイン／サインアップテスト
```bash
# 新規登録
curl -X POST http://localhost:8080/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "Passw0rd!", "full_name": "Player One"}'

# サインイン
curl -X POST http://localhost:8080/auth/signin \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "Passw0rd!"}'
```

### 7.2 HP/MP APIテスト
```bash
# HP取得（認証トークンが必要）
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:8080/api/hp

# HP更新
curl -X PUT \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"hp": 150}' \
  http://localhost:8080/api/hp/update
```

## 8. トラブルシューティング

### 8.1 データベース接続エラー
- 接続文字列が正しいか確認
- ファイアウォール設定を確認
- Supabaseプロジェクトがアクティブか確認

### 8.2 認証エラー
- 送信したメールアドレス／パスワードが正しいか確認
- パスワードは8文字以上か確認
- 同じメールアドレスで既に登録済みでないか確認

### 8.3 マイグレーションエラー
- 既存のテーブルとの競合を確認
- 権限設定を確認
- SQL構文を確認

## 9. 本番環境での注意事項

### 9.1 セキュリティ
- JWT_SECRETを強力なランダム文字列に設定
- 環境変数を適切に管理
- HTTPSを使用

### 9.2 パフォーマンス
- データベース接続プールの設定
- インデックスの最適化
- ログレベルの調整

### 9.3 監視
- アプリケーションログの監視
- データベースパフォーマンスの監視
- エラー率の監視

## 10. 参考リンク

- [Supabase Documentation](https://supabase.com/docs)
- [Go PostgreSQL Driver](https://github.com/lib/pq)
- [JWT Go Library](https://github.com/golang-jwt/jwt)
