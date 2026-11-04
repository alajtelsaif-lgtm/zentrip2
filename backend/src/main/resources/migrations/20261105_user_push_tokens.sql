BEGIN;

DO $$
BEGIN
    IF to_regclass('public.schema_migrations') IS NULL
       OR to_regclass('public.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime')
       OR to_regprocedure('public.zentrip_rls_user_id()') IS NULL
       OR to_regprocedure('public.zentrip_rls_role()') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261105_user_push_tokens requires users and the 20261101_role_access_rls runtime role/helpers';
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
    token TEXT PRIMARY KEY
        CHECK (length(btrim(token)) BETWEEN 1 AND 4096),
    user_id BIGINT NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL
        CHECK (platform IN ('android', 'ios', 'web')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_push_tokens_user_id_index
    ON public.user_push_tokens (user_id);

ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_push_tokens_owner_read
    ON public.user_push_tokens;
CREATE POLICY user_push_tokens_owner_read
    ON public.user_push_tokens
    FOR SELECT TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS user_push_tokens_owner_delete
    ON public.user_push_tokens;
CREATE POLICY user_push_tokens_owner_delete
    ON public.user_push_tokens
    FOR DELETE TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id());

CREATE OR REPLACE FUNCTION public.zentrip_register_user_push_token(
    p_token TEXT,
    p_platform TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id BIGINT := public.zentrip_rls_user_id();
BEGIN
    IF v_user_id IS NULL
       OR public.zentrip_rls_role() NOT IN ('admin', 'partner', 'customer')
       OR p_token IS NULL
       OR p_token <> btrim(p_token)
       OR length(p_token) NOT BETWEEN 1 AND 4096
       OR p_platform IS NULL
       OR p_platform NOT IN ('android', 'ios', 'web') THEN
        RETURN FALSE;
    END IF;

    INSERT INTO public.user_push_tokens (token, user_id, platform)
    VALUES (p_token, v_user_id, p_platform)
    ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id,
            platform = EXCLUDED.platform,
            last_seen_at = NOW();
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.zentrip_register_user_push_token(TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_register_user_push_token(TEXT, TEXT)
    TO zentrip_api_runtime;

GRANT SELECT, DELETE ON public.user_push_tokens TO zentrip_api_runtime;
REVOKE ALL ON public.user_push_tokens FROM PUBLIC, anon, authenticated;

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261105_user_push_tokens', 'user_push_tokens')
ON CONFLICT (version) DO NOTHING;

COMMIT;
