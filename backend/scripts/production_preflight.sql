-- Zentrip production pre-flight check (READ-ONLY).
-- Paste into the Supabase SQL Editor and run. It changes nothing.
-- Each row says whether an object the backend expects exists, and which
-- migration file creates it. Run the migrations whose rows say "MISSING",
-- in the order shown in the README ("Supabase migration order").
-- Turn OFF the SQL Editor's "limit 100 rows" option so no rows are hidden.

WITH checks(sort_order, item, present, fixed_by) AS (
    VALUES
    -- Prerequisites created by the one-time role baseline.
    (1,  'role zentrip_api_runtime',
         EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zentrip_api_runtime'),
         '20261101_role_access_rls.sql (baseline - compare first, do not replay blindly)'),
    (2,  'function public.zentrip_rls_user_id()',
         to_regprocedure('public.zentrip_rls_user_id()') IS NOT NULL,
         '20261101_role_access_rls.sql'),
    (3,  'function public.zentrip_rls_role()',
         to_regprocedure('public.zentrip_rls_role()') IS NOT NULL,
         '20261101_role_access_rls.sql'),
    (4,  'function public.zentrip_rls_partner_id()',
         to_regprocedure('public.zentrip_rls_partner_id()') IS NOT NULL,
         '20261101_role_access_rls.sql'),

    -- Migration ledger.
    (10, 'table public.schema_migrations',
         to_regclass('public.schema_migrations') IS NOT NULL,
         '20261101_schema_migrations.sql'),

    -- Feature tables. When these are missing the API either falls back
    -- (landmarks, hotel destinations, notifications) or FAILS (payments).
    (20, 'tables landmark_places / aliases / search_areas / merge_candidates',
         to_regclass('public.landmark_places') IS NOT NULL
         AND to_regclass('public.landmark_place_aliases') IS NOT NULL
         AND to_regclass('public.landmark_search_areas') IS NOT NULL
         AND to_regclass('public.landmark_merge_candidates') IS NOT NULL,
         '20261102_landmark_catalog.sql'),
    (30, 'table public.hotel_destinations',
         to_regclass('public.hotel_destinations') IS NOT NULL,
         '20261103_hotel_destination_catalog.sql'),
    (40, 'table public.legacy_attraction_partner_reviews',
         to_regclass('public.legacy_attraction_partner_reviews') IS NOT NULL,
         '20261104_core_data_rls.sql'),
    (41, 'RLS enabled on attraction_visit_counts',
         COALESCE((SELECT relrowsecurity FROM pg_class
                   WHERE oid = to_regclass('public.attraction_visit_counts')), FALSE),
         '20261104_core_data_rls.sql'),
    (42, 'RLS enabled on attraction_visit_dedup',
         COALESCE((SELECT relrowsecurity FROM pg_class
                   WHERE oid = to_regclass('public.attraction_visit_dedup')), FALSE),
         '20261104_core_data_rls.sql'),
    (43, 'anon has NO direct INSERT on attraction_visit_counts',
         to_regclass('public.attraction_visit_counts') IS NULL
         OR NOT has_table_privilege('anon', 'public.attraction_visit_counts', 'INSERT'),
         '20261104_core_data_rls.sql'),
    (50, 'table public.payment_attempts  (REQUIRED for every checkout)',
         to_regclass('public.payment_attempts') IS NOT NULL,
         '20261104_payment_attempts.sql'),
    (60, 'table public.user_push_tokens',
         to_regclass('public.user_push_tokens') IS NOT NULL,
         '20261105_user_push_tokens.sql'),
    (70, 'table public.user_notifications',
         to_regclass('public.user_notifications') IS NOT NULL,
         '20261107_user_notifications.sql'),
    (80, 'column offers.flight_listing_id  (REQUIRED to create offers)',
         EXISTS (SELECT 1 FROM pg_attribute
                 WHERE attrelid = to_regclass('public.offers')
                   AND attname = 'flight_listing_id' AND NOT attisdropped),
         '20261107_offer_flight_link.sql')
)
SELECT sort_order,
       item,
       CASE WHEN present THEN 'OK' ELSE 'MISSING' END AS status,
       fixed_by
FROM checks
ORDER BY sort_order;

-- Migrations already recorded (empty / error if the ledger is missing):
-- SELECT version, applied_at FROM public.schema_migrations ORDER BY version;
