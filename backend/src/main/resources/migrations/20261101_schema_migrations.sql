BEGIN;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version VARCHAR(120) PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL ON public.schema_migrations FROM PUBLIC, anon, authenticated;

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261101_schema_migrations', 'schema_migrations')
ON CONFLICT (version) DO NOTHING;

COMMIT;
