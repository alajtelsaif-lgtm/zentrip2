BEGIN;

DO $$
BEGIN
    IF to_regclass('public.schema_migrations') IS NULL
       OR to_regclass('public.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime')
       OR to_regprocedure('public.zentrip_rls_user_id()') IS NULL
       OR to_regprocedure('public.zentrip_rls_role()') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261107_user_notifications requires users and the 20261101_role_access_rls runtime role/helpers';
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_key TEXT NOT NULL
        CHECK (length(btrim(event_key)) BETWEEN 1 AND 200),
    kind TEXT NOT NULL
        CHECK (kind IN ('booking', 'cancel', 'chat', 'promo', 'reminder')),
    title_en TEXT NOT NULL CHECK (length(title_en) BETWEEN 1 AND 255),
    title_ar TEXT NOT NULL CHECK (length(title_ar) BETWEEN 1 AND 255),
    body_en TEXT NOT NULL CHECK (length(body_en) BETWEEN 1 AND 1000),
    body_ar TEXT NOT NULL CHECK (length(body_ar) BETWEEN 1 AND 1000),
    target_type TEXT CHECK (target_type IN ('trip', 'booking')),
    target_id BIGINT,
    booking_ref TEXT CHECK (booking_ref IS NULL OR length(booking_ref) <= 120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    CONSTRAINT user_notifications_event_key_unique UNIQUE (user_id, event_key)
);

CREATE INDEX IF NOT EXISTS user_notifications_user_created_index
    ON public.user_notifications (user_id, created_at DESC, id DESC);

ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_notifications_owner_read
    ON public.user_notifications;
CREATE POLICY user_notifications_owner_read
    ON public.user_notifications
    FOR SELECT TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS user_notifications_owner_insert
    ON public.user_notifications;
CREATE POLICY user_notifications_owner_insert
    ON public.user_notifications
    FOR INSERT TO zentrip_api_runtime
    WITH CHECK (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS user_notifications_owner_update
    ON public.user_notifications;
CREATE POLICY user_notifications_owner_update
    ON public.user_notifications
    FOR UPDATE TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

-- Reset first: the role baseline's GRANT ON ALL TABLES can add DELETE
-- when migrations are replayed; keep exactly the privileges below.
REVOKE ALL ON public.user_notifications FROM zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.user_notifications
    TO zentrip_api_runtime;
GRANT USAGE, SELECT ON SEQUENCE public.user_notifications_id_seq
    TO zentrip_api_runtime;
REVOKE ALL ON public.user_notifications FROM PUBLIC, anon, authenticated;

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261107_user_notifications', 'user_notifications')
ON CONFLICT (version) DO NOTHING;

COMMIT;
