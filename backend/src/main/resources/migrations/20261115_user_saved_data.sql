-- Server-side storage for data the app used to keep only on the device:
-- favorites, flight price alerts, and per-user app settings (notification
-- toggles, language, currency). Owner-scoped through RLS like the other
-- user tables. Safe to rerun.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.schema_migrations') IS NULL
       OR to_regclass('public.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime')
       OR to_regprocedure('public.zentrip_rls_user_id()') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261115_user_saved_data requires users and the 20261101_role_access_rls runtime role/helpers';
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_favorites (
    user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    item_id VARCHAR(512) NOT NULL CHECK (length(btrim(item_id)) > 0),
    item_type VARCHAR(32) NOT NULL CHECK (length(btrim(item_type)) > 0),
    title VARCHAR(255) NOT NULL,
    subtitle VARCHAR(512) NOT NULL DEFAULT '',
    image_url VARCHAR(2048),
    latitude DOUBLE PRECISION CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, item_id)
);
CREATE INDEX IF NOT EXISTS user_favorites_user_created_index
    ON public.user_favorites (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.user_price_alerts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    origin_code VARCHAR(8) NOT NULL CHECK (origin_code ~ '^[A-Z0-9]{2,8}$'),
    destination_code VARCHAR(8) NOT NULL CHECK (destination_code ~ '^[A-Z0-9]{2,8}$'),
    departure_date DATE NOT NULL,
    reference_price_usd NUMERIC(12,2) NOT NULL CHECK (reference_price_usd >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_price_alerts_route_unique
        UNIQUE (user_id, origin_code, destination_code, departure_date)
);
CREATE INDEX IF NOT EXISTS user_price_alerts_user_created_index
    ON public.user_price_alerts (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id BIGINT PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(settings) = 'object'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_price_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_favorites_owner_all ON public.user_favorites;
CREATE POLICY user_favorites_owner_all
    ON public.user_favorites FOR ALL TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS user_price_alerts_owner_all ON public.user_price_alerts;
CREATE POLICY user_price_alerts_owner_all
    ON public.user_price_alerts FOR ALL TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS user_settings_owner_all ON public.user_settings;
CREATE POLICY user_settings_owner_all
    ON public.user_settings FOR ALL TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.user_favorites, public.user_price_alerts, public.user_settings
    TO zentrip_api_runtime;
GRANT USAGE, SELECT ON SEQUENCE public.user_price_alerts_id_seq
    TO zentrip_api_runtime;
REVOKE ALL ON public.user_favorites, public.user_price_alerts, public.user_settings
    FROM PUBLIC, anon, authenticated;

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261115_user_saved_data', 'user_saved_data')
ON CONFLICT (version) DO NOTHING;

COMMIT;
