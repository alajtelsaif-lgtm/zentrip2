-- Run against the existing Supabase database before restarting the backend.
-- This migration adds a non-login runtime role so the JDBC app does not bypass
-- RLS through the postgres/BYPASSRLS connection. It does not alter row data.

DO $$
DECLARE
    existing_role pg_roles%ROWTYPE;
BEGIN
    SELECT * INTO existing_role
    FROM pg_roles
    WHERE rolname = 'zentrip_api_runtime';
    IF NOT FOUND THEN
        CREATE ROLE zentrip_api_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    ELSIF existing_role.rolcanlogin
          OR existing_role.rolsuper
          OR existing_role.rolbypassrls THEN
        RAISE EXCEPTION 'zentrip_api_runtime exists with unsafe role attributes';
    END IF;
END
$$;

GRANT zentrip_api_runtime TO postgres;
GRANT USAGE ON SCHEMA public TO zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
    TO zentrip_api_runtime;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public
    TO zentrip_api_runtime;

CREATE OR REPLACE FUNCTION public.zentrip_rls_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('app.user_id', true), '')::BIGINT,
        public.current_app_user_id()
    )
$$;

CREATE OR REPLACE FUNCTION public.zentrip_rls_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('app.auth_role', true), ''),
        (
            SELECT LOWER(u.role)
            FROM public.users u
            WHERE u.auth_user_id = auth.uid()
            LIMIT 1
        ),
        'anonymous'
    )
$$;

CREATE OR REPLACE FUNCTION public.zentrip_rls_partner_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('app.partner_id', true), '')::BIGINT,
        (
            SELECT u.partner_id
            FROM public.users u
            WHERE u.auth_user_id = auth.uid()
              AND LOWER(u.role) = 'partner'
            LIMIT 1
        )
    )
$$;

GRANT EXECUTE ON FUNCTION public.zentrip_rls_user_id()
    TO zentrip_api_runtime, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_rls_role()
    TO zentrip_api_runtime, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zentrip_rls_partner_id()
    TO zentrip_api_runtime, anon, authenticated;

-- Public catalog reads remain public; writes are restricted to the owner or admin.
DROP POLICY IF EXISTS partner_listings_public_read ON public.partner_listings;
CREATE POLICY partner_listings_public_read
    ON public.partner_listings FOR SELECT TO anon, authenticated
    USING (
        active = TRUE
        AND public.zentrip_rls_role() <> 'partner'
        AND EXISTS (
            SELECT 1 FROM public.partners p
            WHERE p.id = partner_listings.partner_id
              AND LOWER(p.status) = 'active'
        )
    );
CREATE POLICY zentrip_partner_listings_public_runtime
    ON public.partner_listings FOR SELECT TO zentrip_api_runtime
    USING (
        active = TRUE
        AND public.zentrip_rls_role() <> 'partner'
        AND EXISTS (
            SELECT 1 FROM public.partners p
            WHERE p.id = partner_listings.partner_id
              AND LOWER(p.status) = 'active'
        )
    );
CREATE POLICY zentrip_partner_listings_admin
    ON public.partner_listings FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_partner_listings_partner
    ON public.partner_listings FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'partner'
        AND partner_id = public.zentrip_rls_partner_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'partner'
        AND partner_id = public.zentrip_rls_partner_id()
    );

-- Partner rows: active partners are public; a partner can only read its own row.
DROP POLICY IF EXISTS partners_public_read ON public.partners;
CREATE POLICY partners_public_read
    ON public.partners FOR SELECT TO anon, authenticated
    USING (
        LOWER(status) = 'active'
        AND public.zentrip_rls_role() <> 'partner'
    );
CREATE POLICY zentrip_partners_public_runtime
    ON public.partners FOR SELECT TO zentrip_api_runtime
    USING (
        LOWER(status) = 'active'
        AND public.zentrip_rls_role() <> 'partner'
    );
CREATE POLICY zentrip_partners_admin
    ON public.partners FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_partners_owner_read
    ON public.partners FOR SELECT TO zentrip_api_runtime, authenticated
    USING (
        id = public.zentrip_rls_partner_id()
        AND public.zentrip_rls_role() = 'partner'
    );

-- Partner bookings are read-only and must reference a listing owned by that partner.
DROP POLICY IF EXISTS bookings_owner_all ON public.bookings;
CREATE POLICY zentrip_bookings_customer
    ON public.bookings FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_bookings_admin
    ON public.bookings FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_bookings_partner_read
    ON public.bookings FOR SELECT TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'partner'
        AND partner_id = public.zentrip_rls_partner_id()
        AND partner_listing_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.partner_listings l
            WHERE l.id = bookings.partner_listing_id
              AND l.partner_id = public.zentrip_rls_partner_id()
        )
    );

DROP POLICY IF EXISTS trips_owner_all ON public.trips;
CREATE POLICY zentrip_trips_customer
    ON public.trips FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_trips_admin
    ON public.trips FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_trips_partner_read
    ON public.trips FOR SELECT TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'partner'
        AND partner_id = public.zentrip_rls_partner_id()
        AND partner_listing_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.partner_listings l
            WHERE l.id = trips.partner_listing_id
              AND l.partner_id = public.zentrip_rls_partner_id()
        )
    );

DROP POLICY IF EXISTS transfers_owner_all ON public.transfers;
CREATE POLICY zentrip_transfers_customer
    ON public.transfers FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_transfers_admin
    ON public.transfers FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_transfers_partner_read
    ON public.transfers FOR SELECT TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'partner'
        AND partner_id = public.zentrip_rls_partner_id()
        AND partner_listing_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.partner_listings l
            WHERE l.id = transfers.partner_listing_id
              AND l.partner_id = public.zentrip_rls_partner_id()
        )
    );

-- User identity rows are private, except booking-linked customer details for the owning partner.
CREATE POLICY zentrip_users_runtime_self_read
    ON public.users FOR SELECT TO zentrip_api_runtime
    USING (id = public.zentrip_rls_user_id());
CREATE POLICY zentrip_users_customer_update
    ON public.users FOR UPDATE TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'customer'
        AND id = public.zentrip_rls_user_id()
        AND role = 'customer'
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND id = public.zentrip_rls_user_id()
        AND role = 'customer'
        AND partner_id IS NULL
    );
CREATE POLICY zentrip_users_partner_booking_read
    ON public.users FOR SELECT TO zentrip_api_runtime
    USING (
        public.zentrip_rls_role() = 'partner'
        AND role = 'customer'
        AND (
            EXISTS (
                SELECT 1 FROM public.bookings b
                JOIN public.partner_listings l ON l.id = b.partner_listing_id
                WHERE b.user_id = users.id
                  AND b.partner_id = public.zentrip_rls_partner_id()
                  AND l.partner_id = public.zentrip_rls_partner_id()
            )
            OR EXISTS (
                SELECT 1 FROM public.trips t
                JOIN public.partner_listings l ON l.id = t.partner_listing_id
                WHERE t.user_id = users.id
                  AND t.partner_id = public.zentrip_rls_partner_id()
                  AND l.partner_id = public.zentrip_rls_partner_id()
            )
            OR EXISTS (
                SELECT 1 FROM public.transfers x
                JOIN public.partner_listings l ON l.id = x.partner_listing_id
                WHERE x.user_id = users.id
                  AND x.partner_id = public.zentrip_rls_partner_id()
                  AND l.partner_id = public.zentrip_rls_partner_id()
            )
        )
    );
CREATE POLICY zentrip_users_admin
    ON public.users FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

-- Per-user application tables.
DROP POLICY IF EXISTS ai_chat_messages_owner_all ON public.ai_chat_messages;
CREATE POLICY zentrip_ai_chat_owner
    ON public.ai_chat_messages FOR ALL TO zentrip_api_runtime, authenticated
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

CREATE POLICY zentrip_api_tokens_owner
    ON public.api_tokens FOR ALL TO zentrip_api_runtime
    USING (user_id = public.zentrip_rls_user_id())
    WITH CHECK (user_id = public.zentrip_rls_user_id());

DROP POLICY IF EXISTS flight_seat_holds_owner_read ON public.flight_seat_holds;
CREATE POLICY zentrip_flight_seat_holds_customer
    ON public.flight_seat_holds FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_flight_seat_holds_admin
    ON public.flight_seat_holds FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

CREATE POLICY zentrip_airports_public_runtime
    ON public.airports FOR SELECT TO zentrip_api_runtime USING (TRUE);
CREATE POLICY zentrip_catalog_metadata_public_runtime
    ON public.offer_catalog_metadata FOR SELECT TO zentrip_api_runtime USING (TRUE);
CREATE POLICY zentrip_offers_public_runtime
    ON public.offers FOR SELECT TO zentrip_api_runtime USING (is_active = TRUE);
CREATE POLICY zentrip_offers_admin
    ON public.offers FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');
CREATE POLICY zentrip_monuments_public_runtime
    ON public.tourist_monuments FOR SELECT TO zentrip_api_runtime
    USING (is_active = TRUE);
CREATE POLICY zentrip_monuments_admin
    ON public.tourist_monuments FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS travel_preferences_owner_all ON public.travel_preferences;
CREATE POLICY zentrip_travel_preferences_owner
    ON public.travel_preferences FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_travel_preferences_admin
    ON public.travel_preferences FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS user_profiles_owner_all ON public.user_profiles;
CREATE POLICY zentrip_user_profiles_owner
    ON public.user_profiles FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_user_profiles_admin
    ON public.user_profiles FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS transfer_schedules_owner_all ON public.transfer_schedules;
CREATE POLICY zentrip_transfer_schedules_customer
    ON public.transfer_schedules FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND EXISTS (
            SELECT 1 FROM public.transfers t
            WHERE t.id = transfer_schedules.transfer_id
              AND t.user_id = public.zentrip_rls_user_id()
        )
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND EXISTS (
            SELECT 1 FROM public.transfers t
            WHERE t.id = transfer_schedules.transfer_id
              AND t.user_id = public.zentrip_rls_user_id()
        )
    );
CREATE POLICY zentrip_transfer_schedules_admin
    ON public.transfer_schedules FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS user_reviews_owner_write ON public.user_reviews;
CREATE POLICY zentrip_user_reviews_public_runtime
    ON public.user_reviews FOR SELECT TO zentrip_api_runtime USING (TRUE);
CREATE POLICY zentrip_user_reviews_customer
    ON public.user_reviews FOR ALL TO zentrip_api_runtime, authenticated
    USING (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    )
    WITH CHECK (
        public.zentrip_rls_role() = 'customer'
        AND user_id = public.zentrip_rls_user_id()
    );
CREATE POLICY zentrip_user_reviews_admin
    ON public.user_reviews FOR ALL TO zentrip_api_runtime, authenticated
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

-- Ensure owner role reads used by the API are constrained even with legacy direct Supabase users.
