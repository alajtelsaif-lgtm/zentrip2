-- OPTIONAL cleanup of objects the Zentrip backend never reads or writes.
-- Back up the database first. Run only after production_preflight.sql is
-- all "OK" and the app has been checked against the migrated database.
-- Each statement is guarded so it does nothing if the object is absent or
-- holds something unexpected.

BEGIN;

-- 1) flyway_schema_history: left over from an earlier tool. The project
--    tracks migrations in public.schema_migrations instead. Drop it only
--    if it still contains nothing but the single Flyway baseline row.
DO $$
BEGIN
    IF to_regclass('public.flyway_schema_history') IS NULL THEN
        RAISE NOTICE 'flyway_schema_history is already gone.';
    ELSIF EXISTS (SELECT 1 FROM public.flyway_schema_history
                  WHERE type <> 'BASELINE') THEN
        RAISE NOTICE 'Kept flyway_schema_history (it has real migration history).';
    ELSE
        EXECUTE 'DROP TABLE public.flyway_schema_history';
        RAISE NOTICE 'Dropped flyway_schema_history (baseline only).';
    END IF;
END
$$;

-- 2) Laravel-era columns on users that no backend code uses.
--    The API issues its own api_tokens and does not track email
--    verification, so these columns are always NULL or stale.
ALTER TABLE public.users DROP COLUMN IF EXISTS remember_token;
-- Uncomment if you are sure you will not add email verification later:
-- ALTER TABLE public.users DROP COLUMN IF EXISTS email_verified_at;

-- 3) users.auth_user_id (+ FK to auth.users) exists only in production and
--    is unused by the custom-session API. Check it is empty before dropping:
--    SELECT COUNT(*) FROM public.users WHERE auth_user_id IS NOT NULL;
--    If 0 and you will not move to Supabase Auth:
-- ALTER TABLE public.users DROP COLUMN IF EXISTS auth_user_id;

COMMIT;
