-- Additive airport-directory migration. It preserves existing airport rows.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.airports') IS NULL
       OR to_regclass('public.schema_migrations') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261101_global_airport_directory requires public.airports and schema_migrations; apply the base schema and migration tracker first';
    END IF;
END
$$;

ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS icao_code CHAR(4);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS airport_type VARCHAR(32) NOT NULL DEFAULT 'medium_airport';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS is_major BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS scheduled_service BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS iso_country CHAR(2);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS keywords TEXT NOT NULL DEFAULT '';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS wikipedia_link VARCHAR(2048);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS source_id BIGINT;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS source_provider VARCHAR(32) NOT NULL DEFAULT 'legacy';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS airports_icao_code_index ON public.airports (icao_code);
CREATE INDEX IF NOT EXISTS airports_country_city_index ON public.airports (iso_country, city);
CREATE INDEX IF NOT EXISTS airports_city_search_index ON public.airports (LOWER(city));
CREATE INDEX IF NOT EXISTS airports_country_search_index ON public.airports (LOWER(country));
CREATE INDEX IF NOT EXISTS airports_name_search_index ON public.airports (LOWER(airport_name));
CREATE INDEX IF NOT EXISTS airports_coordinates_index ON public.airports (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261101_global_airport_directory', 'global_airport_directory')
ON CONFLICT (version) DO NOTHING;

COMMIT;
