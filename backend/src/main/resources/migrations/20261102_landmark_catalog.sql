-- Additive worldwide landmark cache. Existing tourist_monuments data is untouched.
-- Run against the target Supabase database deliberately before enabling the catalog.

CREATE TABLE IF NOT EXISTS public.landmark_places (
    id UUID PRIMARY KEY,
    canonical_place_id UUID NULL REFERENCES public.landmark_places(id) ON DELETE RESTRICT,
    provider VARCHAR(40) NOT NULL,
    provider_place_id VARCHAR(100) NOT NULL,
    wikidata_id VARCHAR(40) NULL,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    category VARCHAR(100) NOT NULL DEFAULT 'landmark',
    rate SMALLINT NOT NULL DEFAULT 0 CHECK (rate BETWEEN 0 AND 3),
    city VARCHAR(255) NOT NULL DEFAULT '',
    country VARCHAR(255) NOT NULL DEFAULT '',
    image_url TEXT NOT NULL DEFAULT '',
    names JSONB NOT NULL DEFAULT '{}'::jsonb,
    descriptions JSONB NOT NULL DEFAULT '{}'::jsonb,
    payload JSONB NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT landmark_places_not_self_canonical
        CHECK (canonical_place_id IS NULL OR canonical_place_id <> id),
    CONSTRAINT landmark_places_provider_identity
        UNIQUE (provider, provider_place_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS landmark_places_wikidata_root_unique
    ON public.landmark_places (wikidata_id)
    WHERE wikidata_id IS NOT NULL AND canonical_place_id IS NULL;
CREATE INDEX IF NOT EXISTS landmark_places_coordinates_index
    ON public.landmark_places (latitude, longitude);
CREATE INDEX IF NOT EXISTS landmark_places_city_country_index
    ON public.landmark_places (LOWER(country), LOWER(city));
CREATE INDEX IF NOT EXISTS landmark_places_category_rate_index
    ON public.landmark_places (category, rate DESC);
CREATE INDEX IF NOT EXISTS landmark_places_canonical_index
    ON public.landmark_places (canonical_place_id)
    WHERE canonical_place_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.landmark_place_aliases (
    id BIGSERIAL PRIMARY KEY,
    canonical_place_id UUID NOT NULL
        REFERENCES public.landmark_places(id) ON DELETE CASCADE,
    alias_name VARCHAR(500) NOT NULL,
    normalized_name VARCHAR(500) NOT NULL,
    language VARCHAR(16) NOT NULL DEFAULT 'en',
    source VARCHAR(40) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT landmark_place_alias_unique
        UNIQUE (canonical_place_id, normalized_name, language, source)
);
CREATE INDEX IF NOT EXISTS landmark_place_alias_name_index
    ON public.landmark_place_aliases (normalized_name text_pattern_ops);

CREATE TABLE IF NOT EXISTS public.landmark_search_areas (
    cache_key VARCHAR(64) PRIMARY KEY,
    area_kind VARCHAR(40) NOT NULL,
    query_text VARCHAR(500) NOT NULL DEFAULT '',
    language VARCHAR(16) NOT NULL DEFAULT 'en',
    south DOUBLE PRECISION NULL,
    west DOUBLE PRECISION NULL,
    north DOUBLE PRECISION NULL,
    east DOUBLE PRECISION NULL,
    request_payload JSONB NOT NULL,
    response_payload JSONB NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT landmark_search_areas_valid_bounds
        CHECK (south IS NULL OR north IS NULL OR south <= north)
);
CREATE INDEX IF NOT EXISTS landmark_search_areas_expiry_index
    ON public.landmark_search_areas (expires_at);
CREATE INDEX IF NOT EXISTS landmark_search_areas_bounds_index
    ON public.landmark_search_areas (south, west, north, east);

CREATE TABLE IF NOT EXISTS public.landmark_merge_candidates (
    id UUID PRIMARY KEY,
    left_place_id UUID NOT NULL
        REFERENCES public.landmark_places(id) ON DELETE CASCADE,
    right_place_id UUID NOT NULL
        REFERENCES public.landmark_places(id) ON DELETE CASCADE,
    distance_meters DOUBLE PRECISION NOT NULL CHECK (distance_meters >= 0),
    confidence NUMERIC(4,3) NULL CHECK (confidence BETWEEN 0 AND 1),
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'merged', 'separate', 'rejected')),
    reviewed_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT landmark_merge_pair_order CHECK (left_place_id < right_place_id),
    CONSTRAINT landmark_merge_pair_unique UNIQUE (left_place_id, right_place_id)
);
CREATE INDEX IF NOT EXISTS landmark_merge_candidates_status_index
    ON public.landmark_merge_candidates (status, created_at);

ALTER TABLE public.landmark_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.landmark_place_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.landmark_search_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.landmark_merge_candidates ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.landmark_places TO zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.landmark_place_aliases TO zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.landmark_search_areas TO zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.landmark_merge_candidates TO zentrip_api_runtime;
GRANT USAGE, SELECT ON SEQUENCE public.landmark_place_aliases_id_seq
    TO zentrip_api_runtime;

DROP POLICY IF EXISTS zentrip_landmark_places_runtime ON public.landmark_places;
DROP POLICY IF EXISTS zentrip_landmark_aliases_runtime ON public.landmark_place_aliases;
DROP POLICY IF EXISTS zentrip_landmark_search_areas_runtime ON public.landmark_search_areas;
DROP POLICY IF EXISTS zentrip_landmark_merge_candidates_runtime ON public.landmark_merge_candidates;

CREATE POLICY zentrip_landmark_places_runtime
    ON public.landmark_places FOR ALL TO zentrip_api_runtime
    USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY zentrip_landmark_aliases_runtime
    ON public.landmark_place_aliases FOR ALL TO zentrip_api_runtime
    USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY zentrip_landmark_search_areas_runtime
    ON public.landmark_search_areas FOR ALL TO zentrip_api_runtime
    USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY zentrip_landmark_merge_candidates_runtime
    ON public.landmark_merge_candidates FOR ALL TO zentrip_api_runtime
    USING (TRUE) WITH CHECK (TRUE);
