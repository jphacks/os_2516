-- Enum definitions for game events
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'game_event_category') THEN
        CREATE TYPE public.game_event_category AS ENUM ('attack', 'heal');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'game_event_type') THEN
        CREATE TYPE public.game_event_type AS ENUM ('fire');
    END IF;
END
$$;

-- Core session table (winner FK added after game_users creation)
CREATE TABLE IF NOT EXISTS public.game_sessions (
    id UUID PRIMARY KEY,
    title TEXT,
    mode TEXT NOT NULL,
    status TEXT NOT NULL,
    arena_lat NUMERIC(9,6),
    arena_lng NUMERIC(9,6),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    winner_user_id UUID,
    result_summary JSONB,
    referee_note TEXT
);

-- Session participants
CREATE TABLE IF NOT EXISTS public.game_users (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES public.players(id),
    role TEXT NOT NULL,
    join_at TIMESTAMPTZ DEFAULT now(),
    leave_at TIMESTAMPTZ,
    initial_hp SMALLINT DEFAULT 100,
    initial_mana SMALLINT DEFAULT 0,
    outcome TEXT,
    final_hp SMALLINT,
    UNIQUE (session_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_game_users_session_role
    ON public.game_users (session_id, role);

-- Winner FK (added after game_users is available to avoid circular dependency)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'game_sessions_winner_user_fk'
    ) THEN
        ALTER TABLE public.game_sessions
            ADD CONSTRAINT game_sessions_winner_user_fk
            FOREIGN KEY (winner_user_id) REFERENCES public.game_users(id);
    END IF;
END
$$;

-- Event logs for combat and other actions
CREATE TABLE IF NOT EXISTS public.game_events (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    trigger_id UUID NOT NULL REFERENCES public.players(id),
    target_id UUID REFERENCES public.players(id),
    trigger_hp SMALLINT,
    target_hp SMALLINT,
    category public.game_event_category NOT NULL,
    type public.game_event_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_events_session_created_at
    ON public.game_events (session_id, created_at);
