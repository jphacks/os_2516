-- プレイヤーテーブル作成
-- DB_DESIGN.mdに基づく設計

-- プレイヤーマスタテーブル
CREATE TABLE IF NOT EXISTS players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    hp SMALLINT NOT NULL DEFAULT 100,
    mp SMALLINT NOT NULL DEFAULT 100,
    rank SMALLINT DEFAULT 0,
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- インデックスの作成
CREATE INDEX IF NOT EXISTS idx_players_user_id ON players(user_id);
CREATE INDEX IF NOT EXISTS idx_players_display_name ON players(display_name);

-- 既存のusersテーブルにHP/MPカラムが追加されていた場合のクリーンアップ
-- （もし存在する場合のみ削除）
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'users' AND column_name = 'hp') THEN
        ALTER TABLE users DROP COLUMN hp;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'users' AND column_name = 'mp') THEN
        ALTER TABLE users DROP COLUMN mp;
    END IF;
END $$;
