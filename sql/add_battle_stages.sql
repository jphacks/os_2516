CREATE TABLE IF NOT EXISTS public.battle_stages (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    latitude NUMERIC(9,6) NOT NULL,
    longitude NUMERIC(9,6) NOT NULL,
    radius_m NUMERIC(6,2),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.game_sessions
    ADD COLUMN IF NOT EXISTS battle_stage_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'game_sessions_battle_stage_fk'
    ) THEN
        ALTER TABLE public.game_sessions
            ADD CONSTRAINT game_sessions_battle_stage_fk
            FOREIGN KEY (battle_stage_id) REFERENCES public.battle_stages(id);
    END IF;
END
$$;

ALTER TABLE public.game_sessions
    DROP COLUMN IF EXISTS arena_lat,
    DROP COLUMN IF EXISTS arena_lng;
