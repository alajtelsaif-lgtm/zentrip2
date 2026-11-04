-- Additive local destination catalog for hotel search autocomplete.
-- Existing hotel listings and booking records are unchanged.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.schema_migrations') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime')
       OR to_regprocedure('public.zentrip_rls_user_id()') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261103_hotel_destination_catalog requires 20261101_role_access_rls and its zentrip_api_runtime role/helpers';
    END IF;
END
$$;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS public.hotel_destinations (
    destination_type VARCHAR(16) NOT NULL
        CHECK (destination_type IN ('city', 'zone', 'country')),
    destination_code VARCHAR(32) NOT NULL,
    parent_code VARCHAR(32) NOT NULL DEFAULT '',
    name_en VARCHAR(255) NOT NULL DEFAULT '',
    name_ar VARCHAR(255) NOT NULL DEFAULT '',
    country_code VARCHAR(3) NOT NULL DEFAULT '',
    country_name_en VARCHAR(255) NOT NULL DEFAULT '',
    country_name_ar VARCHAR(255) NOT NULL DEFAULT '',
    latitude DOUBLE PRECISION NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NULL CHECK (longitude BETWEEN -180 AND 180),
    search_text TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (destination_type, destination_code, parent_code)
);

CREATE INDEX IF NOT EXISTS hotel_destinations_search_trgm_index
    ON public.hotel_destinations USING GIN (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS hotel_destinations_type_name_index
    ON public.hotel_destinations (destination_type, LOWER(name_en));
CREATE INDEX IF NOT EXISTS hotel_destinations_updated_at_index
    ON public.hotel_destinations (updated_at DESC);

ALTER TABLE public.hotel_destinations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.hotel_destinations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.hotel_destinations
    TO zentrip_api_runtime;

DROP POLICY IF EXISTS hotel_destinations_public_read
    ON public.hotel_destinations;

DROP POLICY IF EXISTS hotel_destinations_runtime_manage
    ON public.hotel_destinations;
CREATE POLICY hotel_destinations_runtime_manage
    ON public.hotel_destinations FOR ALL TO zentrip_api_runtime
    USING (TRUE)
    WITH CHECK (TRUE);

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261103_hotel_destination_catalog', 'hotel_destination_catalog')
ON CONFLICT (version) DO NOTHING;

COMMIT;
