-- Enable the row policies for all application tables after the full schema
-- and feature-migration chain has been applied.
-- The application uses zentrip_api_runtime for request-time database work.

-- These values are populated by RlsContextFilter from the verified session.
-- Do not derive application roles from a client-supplied claim or from a
-- Supabase auth_user_id column; this project uses its own users/api_tokens.
CREATE OR REPLACE FUNCTION public.zentrip_rls_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT NULLIF(current_setting('app.user_id', TRUE), '')::BIGINT
$$;

CREATE OR REPLACE FUNCTION public.zentrip_rls_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(NULLIF(current_setting('app.auth_role', TRUE), ''), 'anonymous')
$$;

CREATE OR REPLACE FUNCTION public.zentrip_rls_partner_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT NULLIF(current_setting('app.partner_id', TRUE), '')::BIGINT
$$;

GRANT EXECUTE ON FUNCTION public.zentrip_rls_user_id()
    TO zentrip_api_runtime, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_rls_role()
    TO zentrip_api_runtime, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_rls_partner_id()
    TO zentrip_api_runtime, anon, authenticated;

-- Inventory changes go through this narrow SECURITY DEFINER function instead
-- of granting customers UPDATE access to every column of public listings.
CREATE OR REPLACE FUNCTION public.zentrip_adjust_listing_inventory(
    p_listing_id BIGINT,
    p_inventory_kind TEXT,
    p_amount INTEGER,
    p_restore BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_listing_id IS NULL OR p_amount IS NULL OR p_amount < 1 OR p_amount > 10000
       OR p_inventory_kind IS NULL
       OR p_inventory_kind NOT IN ('hotel_rooms', 'car_vehicles', 'flight_seats')
       OR public.zentrip_rls_role() NOT IN ('customer', 'admin')
       OR (public.zentrip_rls_role() = 'customer'
           AND public.zentrip_rls_user_id() IS NULL) THEN
        RETURN FALSE;
    END IF;

    IF p_inventory_kind = 'hotel_rooms' AND p_restore THEN
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{available_rooms}',
                to_jsonb(available_rooms + p_amount),
                TRUE),
            available_rooms = available_rooms + p_amount,
            updated_at = NOW()
        WHERE id = p_listing_id AND type = 'hotel';
    ELSIF p_inventory_kind = 'hotel_rooms' THEN
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{available_rooms}',
                to_jsonb(available_rooms - p_amount),
                TRUE),
            available_rooms = available_rooms - p_amount,
            updated_at = NOW()
        WHERE id = p_listing_id
          AND type = 'hotel'
          AND active = TRUE
          AND available_rooms >= p_amount
          AND EXISTS (
              SELECT 1 FROM public.partners p
              WHERE p.id = partner_listings.partner_id
                AND LOWER(p.status) = 'active'
          );
    ELSIF p_inventory_kind = 'car_vehicles' AND p_restore THEN
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{available_vehicles}',
                to_jsonb(COALESCE((attributes ->> 'available_vehicles')::INTEGER, 0) + p_amount),
                TRUE),
            updated_at = NOW()
        WHERE id = p_listing_id AND type = 'car';
    ELSIF p_inventory_kind = 'car_vehicles' THEN
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{available_vehicles}',
                to_jsonb(COALESCE((attributes ->> 'available_vehicles')::INTEGER, 1) - p_amount),
                TRUE),
            updated_at = NOW()
        WHERE id = p_listing_id
          AND type = 'car'
          AND active = TRUE
          AND COALESCE((attributes ->> 'available_vehicles')::INTEGER, 1) >= p_amount
          AND EXISTS (
              SELECT 1 FROM public.partners p
              WHERE p.id = partner_listings.partner_id
                AND LOWER(p.status) = 'active'
          );
    ELSIF p_inventory_kind = 'flight_seats' AND p_restore THEN
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{seats_available}',
                to_jsonb(COALESCE((attributes ->> 'seats_available')::INTEGER, 0) + p_amount),
                TRUE),
            updated_at = NOW()
        WHERE id = p_listing_id AND type = 'flight';
    ELSE
        UPDATE public.partner_listings
        SET attributes = jsonb_set(
                COALESCE(attributes, '{}'::jsonb),
                '{seats_available}',
                to_jsonb(COALESCE((attributes ->> 'seats_available')::INTEGER, 0) - p_amount),
                TRUE),
            updated_at = NOW()
        WHERE id = p_listing_id
          AND type = 'flight'
          AND active = TRUE
          AND COALESCE((attributes ->> 'seats_available')::INTEGER, 0) >= p_amount
          AND EXISTS (
              SELECT 1 FROM public.partners p
              WHERE p.id = partner_listings.partner_id
                AND LOWER(p.status) = 'active'
          );
    END IF;

    RETURN FOUND;
END
$$;

REVOKE ALL ON FUNCTION public.zentrip_adjust_listing_inventory(BIGINT, TEXT, INTEGER, BOOLEAN)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_adjust_listing_inventory(BIGINT, TEXT, INTEGER, BOOLEAN)
    TO zentrip_api_runtime;

-- Seat reservations need one serialization point without customer UPDATE
-- permissions on the listing row. The row lock remains held by the request
-- transaction while the application creates its seat holds.
CREATE OR REPLACE FUNCTION public.zentrip_lock_flight_listing(p_listing_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF public.zentrip_rls_role() NOT IN ('customer', 'admin')
       OR (public.zentrip_rls_role() = 'customer'
           AND public.zentrip_rls_user_id() IS NULL) THEN
        RETURN FALSE;
    END IF;

    PERFORM l.id
    FROM public.partner_listings l
    JOIN public.partners p ON p.id = l.partner_id
    WHERE l.id = p_listing_id
      AND l.type = 'flight'
      AND l.active = TRUE
      AND LOWER(p.status) = 'active'
    FOR UPDATE OF l;
    RETURN FOUND;
END
$$;

REVOKE ALL ON FUNCTION public.zentrip_lock_flight_listing(BIGINT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_lock_flight_listing(BIGINT)
    TO zentrip_api_runtime;

DO $$
DECLARE
    table_name TEXT;
    core_tables TEXT[] := ARRAY[
        'partners',
        'users',
        'password_reset_codes',
        'partner_listings',
        'airports',
        'user_reviews',
        'user_profiles',
        'ai_chat_messages',
        'travel_preferences',
        'tourist_monuments',
        'legacy_attraction_partner_reviews',
        'attraction_visit_counts',
        'attraction_visit_dedup',
        'offers',
        'offer_catalog_metadata',
        'trips',
        'flight_seat_holds',
        'bookings',
        'transfers',
        'transfer_schedules',
        'api_tokens',
        'hotel_destinations',
        'landmark_places',
        'landmark_place_aliases',
        'landmark_search_areas',
        'landmark_merge_candidates'
    ];
BEGIN
    FOREACH table_name IN ARRAY core_tables LOOP
        IF to_regclass('public.' || quote_ident(table_name)) IS NOT NULL THEN
            EXECUTE format(
                'ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',
                table_name
            );
        END IF;
    END LOOP;
END
$$;

-- Public auth flows may look up only the email currently being processed.
-- The API sets this transaction-local value after validating the request.
DROP POLICY IF EXISTS zentrip_users_auth_email_lookup ON public.users;
CREATE POLICY zentrip_users_auth_email_lookup
    ON public.users FOR SELECT TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'anonymous'
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
    );

DROP POLICY IF EXISTS zentrip_users_registration_insert ON public.users;
CREATE POLICY zentrip_users_registration_insert
    ON public.users FOR INSERT TO zentrip_api_runtime
    WITH CHECK (
        public.zentrip_rls_role() = 'anonymous'
        AND role = 'customer'
        AND partner_id IS NULL
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
    );

DROP POLICY IF EXISTS zentrip_users_password_reset_update ON public.users;
CREATE POLICY zentrip_users_password_reset_update
    ON public.users FOR UPDATE TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'password_reset'
        AND id = public.zentrip_rls_user_id()
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'password_reset'
        AND id = public.zentrip_rls_user_id()
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
        AND role IN ('admin', 'partner', 'customer')
    );

-- Password-reset rows are private to the one email handled in this request.
DROP POLICY IF EXISTS zentrip_password_reset_codes_email ON public.password_reset_codes;
CREATE POLICY zentrip_password_reset_codes_email
    ON public.password_reset_codes FOR ALL TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() IN ('anonymous', 'password_reset')
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
    )
    WITH CHECK (
        public.zentrip_rls_role() IN ('anonymous', 'password_reset')
        AND LOWER(email) = LOWER(NULLIF(current_setting('app.auth_email', TRUE), ''))
    );

-- Minted sessions are inserted only after the controller has authenticated
-- the user and set the verified user ID and database-derived role.
DROP POLICY IF EXISTS zentrip_api_tokens_authenticated_insert ON public.api_tokens;
CREATE POLICY zentrip_api_tokens_authenticated_insert
    ON public.api_tokens FOR INSERT TO zentrip_api_runtime
    WITH CHECK (
        user_id = public.zentrip_rls_user_id()
        AND public.zentrip_rls_role() IN ('admin', 'partner', 'customer')
    );

-- A partner may read schedule rows only for its own partner-linked transfers.
DROP POLICY IF EXISTS zentrip_transfer_schedules_partner_read
    ON public.transfer_schedules;
CREATE POLICY zentrip_transfer_schedules_partner_read
    ON public.transfer_schedules FOR SELECT TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'partner'
        AND EXISTS (
            SELECT 1
            FROM public.transfers t
            JOIN public.partner_listings l ON l.id = t.partner_listing_id
            WHERE t.id = transfer_schedules.transfer_id
              AND t.partner_id = public.zentrip_rls_partner_id()
              AND l.partner_id = public.zentrip_rls_partner_id()
        )
    );

-- Authenticated partners may read their own avatar in /auth/me, but cannot
-- edit customer profile data through this policy.
DROP POLICY IF EXISTS zentrip_user_profiles_partner_self_read
    ON public.user_profiles;
CREATE POLICY zentrip_user_profiles_partner_self_read
    ON public.user_profiles FOR SELECT TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'partner'
        AND user_id = public.zentrip_rls_user_id()
    );

-- Internal aggregate counters are written only through the rate-limited visit
-- endpoint and read by attraction/admin handlers. They contain no raw IP data.
DROP POLICY IF EXISTS zentrip_attraction_visit_counts_runtime
    ON public.attraction_visit_counts;
CREATE POLICY zentrip_attraction_visit_counts_runtime
    ON public.attraction_visit_counts FOR ALL TO zentrip_api_runtime
    USING (public.zentrip_rls_role() IN ('anonymous', 'customer', 'admin'))
    WITH CHECK (public.zentrip_rls_role() IN ('anonymous', 'customer', 'admin'));

DROP POLICY IF EXISTS zentrip_attraction_visit_dedup_runtime
    ON public.attraction_visit_dedup;
CREATE POLICY zentrip_attraction_visit_dedup_runtime
    ON public.attraction_visit_dedup FOR ALL TO zentrip_api_runtime
    USING (public.zentrip_rls_role() IN ('anonymous', 'customer', 'admin'))
    WITH CHECK (public.zentrip_rls_role() IN ('anonymous', 'customer', 'admin'));

-- Legacy attraction review records are an admin-only moderation surface.
DROP POLICY IF EXISTS zentrip_legacy_attraction_reviews_admin
    ON public.legacy_attraction_partner_reviews;
CREATE POLICY zentrip_legacy_attraction_reviews_admin
    ON public.legacy_attraction_partner_reviews FOR ALL TO zentrip_api_runtime
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

