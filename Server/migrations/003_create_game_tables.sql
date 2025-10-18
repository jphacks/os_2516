-- ゲームセッション関連テーブルの作成

CREATE TABLE IF NOT EXISTS game_sessions (
    id UUID PRIMARY KEY,
    stage_id UUID NOT NULL,
    mode TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_game_sessions_stage ON game_sessions(stage_id);

CREATE TABLE IF NOT EXISTS game_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    initial_hp SMALLINT NOT NULL DEFAULT 100,
    initial_mp SMALLINT NOT NULL DEFAULT 100,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_game_users_session_id ON game_users(session_id);

CREATE TABLE IF NOT EXISTS player_state_snapshots (
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    hp SMALLINT NOT NULL,
    mp SMALLINT NOT NULL,
    stance TEXT,
    last_position_id UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (session_id, player_id)
);

CREATE TABLE IF NOT EXISTS game_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    trigger_id UUID NOT NULL REFERENCES players(id),
    target_id UUID NOT NULL REFERENCES players(id),
    trigger_hp SMALLINT NOT NULL,
    target_hp SMALLINT NOT NULL,
    trigger_mp SMALLINT,
    target_mp SMALLINT,
    category TEXT NOT NULL,
    type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_game_events_session ON game_events(session_id, created_at);
