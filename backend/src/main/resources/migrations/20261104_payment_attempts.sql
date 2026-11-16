BEGIN;

DO $$
BEGIN
    IF to_regclass('public.schema_migrations') IS NULL
       OR to_regclass('public.users') IS NULL
       OR to_regclass('public.bookings') IS NULL
       OR to_regclass('public.trips') IS NULL
       OR to_regclass('public.transfers') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime')
       OR to_regprocedure('public.zentrip_rls_user_id()') IS NULL THEN
        RAISE EXCEPTION 'Migration 20261104_payment_attempts requires users, bookings, trips, transfers, and the 20261101_role_access_rls runtime role/helpers';
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.payment_attempts (
    id BIGSERIAL PRIMARY KEY,
    session_id VARCHAR(128) NOT NULL UNIQUE,
    booking_id BIGINT NULL UNIQUE
        REFERENCES public.bookings(id) ON DELETE SET NULL,
    trip_id BIGINT NULL UNIQUE
        REFERENCES public.trips(id) ON DELETE SET NULL,
    transfer_id BIGINT NULL UNIQUE
        REFERENCES public.transfers(id) ON DELETE SET NULL,
    user_id BIGINT NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    status VARCHAR(10) NOT NULL CHECK (status IN ('success', 'failed')),
    is_simulation BOOLEAN NOT NULL DEFAULT TRUE CHECK (is_simulation = TRUE),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT payment_attempts_single_booking_link
        CHECK (num_nonnulls(booking_id, trip_id, transfer_id) <= 1)
);

CREATE INDEX IF NOT EXISTS payment_attempts_user_created_index
    ON public.payment_attempts (user_id, created_at DESC);

ALTER TABLE public.payment_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_attempts FROM PUBLIC, anon, authenticated;
-- Reset first: the role baseline's GRANT ON ALL TABLES can add DELETE
-- when migrations are replayed; keep exactly the privileges below.
REVOKE ALL ON public.payment_attempts FROM zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.payment_attempts TO zentrip_api_runtime;
GRANT USAGE, SELECT ON SEQUENCE public.payment_attempts_id_seq
    TO zentrip_api_runtime;

DROP POLICY IF EXISTS zentrip_payment_attempts_owner
    ON public.payment_attempts;
CREATE POLICY zentrip_payment_attempts_owner
    ON public.payment_attempts FOR ALL TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261104_payment_attempts', 'payment_attempts')
ON CONFLICT (version) DO NOTHING;

COMMIT;
