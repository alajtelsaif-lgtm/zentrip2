# Zentrip database persistence verification

**Verification date:** 2026-11-04  
**Scope:** Flutter-to-API persistence paths, PostgreSQL/Supabase schema alignment, RLS, and local PostgreSQL test coverage.  
**Production safety:** This work used only an isolated local PostgreSQL database. The production metadata below is from the prior read-only audit; Supabase was not queried or changed during this implementation. No production rows, schema, migrations, or accounts were changed.

## Executive summary

The local implementation now includes migration tracking, visit-table permission hardening, transfer history, persisted flight seats/extras, and a simulator-only payment-attempt ledger. A fresh local PostgreSQL instance passed the full migration/backend suite, and Flutter analysis and tests passed.

The live Supabase schema is **not fully aligned** with the current migrations:

- The prior audit found 21 public tables, including `flyway_schema_history`; the current schema plus migrations expects 28 application tables, plus the new private `schema_migrations` ledger.
- Seven expected feature tables were missing in that audit: `hotel_destinations`, four landmark catalog tables, `legacy_attraction_partner_reviews`, and `user_push_tokens`. The new payment-ledger migration adds an eighth expected application table, `payment_attempts`.
- `attraction_visit_counts` and `attraction_visit_dedup` have RLS disabled in Supabase. The `anon` and `authenticated` roles also have direct table `SELECT` and `INSERT` privileges. This bypasses the application endpoint’s visit limits and is the highest-priority issue.
- `flyway_schema_history` contains only a baseline row, so it does not establish which SQL migrations ran or in what order.
- Transfers are now loaded by My Trips through the authenticated, user-scoped `/api/transfers` route.
- Favorites, price alerts, notification preferences, locale, and currency are device-local, not Supabase-synced.
- The app’s payment flow remains explicitly simulated. Local code now records success/failure attempts and links successful attempts to a booking, flight trip, or transfer; this does not prove that money was captured.

**Readiness:** Not ready for a complete persistence or production-safety sign-off. Core booking writes have local PostgreSQL test coverage, but live booking writes were deliberately not attempted. Fix the visit-table access and reconcile the missing migrations before relying on all advertised persistence features.

## 1. Screen-to-storage inventory

“Local test” means the route or database behavior was exercised in the temporary PostgreSQL test environment, not against customer data in Supabase.

| Screen/action | Flutter call and API path | Backend path | Database write and result |
|---|---|---|---|
| Register, sign in, sign out | `ApiService` auth methods → `/api/auth/*` | `ApiController` auth handlers | Registration writes `users` (`name`, `email`, `phone`, `password`, role, timestamps), optional `user_profiles` (`user_id`, `photo_url`, timestamps), and an `api_tokens` record (`user_id`, `token_hash`, `expires_at`, `created_at`). Login creates a token; logout removes that token. Registration/login were covered by backend/PostgreSQL tests. |
| Forgot/reset password | `ApiService` password recovery methods → `/api/auth/*` | `PasswordResetService` and auth handlers | Writes `password_reset_codes` (`email`, `code_hash`, `created_at`, `expires_at`, `attempts`), updates `users.password`, and invalidates tokens/reset records as appropriate. The code hash, not the six-digit code, is stored. Unit tests passed; the recovery flow was not run against a live mailbox or production account. |
| Profile and profile photo | `ApiService` profile methods → `/api/profile` | `ApiController` and `ProfilePhotoStorage` | Updates `users.name`, `phone`, `updated_at`; stores the photo URL in `user_profiles.photo_url`. Image bytes are written to the backend’s local `uploads/` directory, not Supabase Storage. The URL can remain in Postgres while the file is lost on an ephemeral/replaced server. |
| Travel preferences | `saveTravelPreferences` → `/api/preferences/travel` | `TravelPreferencesController` | Upserts one row in `travel_preferences` by `user_id`: `budget_level`, `travel_pace`, `trip_duration_days`, `travelers`, `interests`, `preferred_destination`, `updated_at`. PostgreSQL upsert test passed. |
| Reviews | `submitReview` → `/api/reviews` | `ApiController` | Upserts `user_reviews` (`user_id`, `item_id`, `item_type`, `rating`, `comment`, timestamps). The review API uses the current user identity. No production review rows were inspected. |
| Zen AI conversation | Chat screen → `/api/ai/chat` | `AiChatController` | Writes paired rows to `ai_chat_messages` (`user_id`, `session_id`, `role`, `content`, `created_at`) and trims old session history. **Persistence failure is caught and logged, but the endpoint still emits `done`; a successful-looking chat response therefore does not guarantee the database write succeeded.** The Flutter history view also uses device-local `SharedPreferences`; it does not fetch the conversation list from the server. |
| Attraction visit count | Attraction screen → `/api/attractions/{id}/visits` | `ApiController` visit handler | Inserts into `attraction_visit_dedup` and increments `attraction_visit_counts`. The local migration enables RLS, revokes direct anon/authenticated table privileges, and preserves runtime-role API access; local PostgreSQL tests verify the permission boundary and route behavior. Production remains unchanged. |
| Partner flight booking | Flight checkout → `/api/bookings/confirm` | `ApiController` transactional confirmation | Creates a `trips` row (`user_id`, flight route/date fields, airline/flight, class, price, `booking_ref`, status, `details`) and confirms the matching `flight_seat_holds` (`flight_listing_id`, `seat_number`, `user_id`, `trip_id`, status, `booking_ref`, expiry/timestamps). `details` includes selected seats and extras. Local tests cover inventory reservation, rollback, cancellation, and customer isolation. |
| Duffel flight booking | Flight checkout → `/api/trips` | `ApiController` trip creation | Creates a `trips` row with route, dates, flight, class, price, reference, passenger count and provider metadata; selected seats and extras now persist in `details` and return to My Trips/ticket details. The successful simulator attempt can be linked to the trip. |
| Hotel, car, package, attraction booking | Detail/checkout screens → `/api/bookings` | `ApiController` booking creation and inventory service | Creates `bookings` (`user_id`, `partner_id`, `partner_listing_id`, `trip_id`, `type`, `status`, `total_amount`, `title`, `subtitle`, `date`, `price`, `ref_code`, `details`, timestamps). `details` currently includes supported values such as end date, image URL, room count/reservation flag, and vehicle reservation flag. Reservation changes are transactional; local tests cover hotel/car booking, cancellation, and inventory rollback. For external hotel results, the persisted summary does not include a LiteAPI hotel/offer ID or a durable provider reference. |
| Transfer booking | Transfer checkout → `/api/transfers` | `ApiController` transfer creation | Transactionally inserts `transfers` and `transfer_schedules`; My Trips now loads the current user’s transfers with a Transfers filter and detail view. The simulator attempt can be linked to the transfer. |
| Partner listing management | Partner dashboard → `/api/partner/listings` | `PartnerController` | Creates/updates/delists `partner_listings`: partner ID, type, title, city/country, description, image URL, price/active state, JSON attributes, hotel location/map/place/rating/review/amenity/tax/room fields, timestamps. Queries scope mutations by the authenticated partner ID. Listing creation and role-isolation tests passed locally. Uploaded image files are local disk files, not object storage. |
| Admin partner management | Admin dashboard → `/api/admin/partners` | `AdminController` | Creates `partners` (`slug`, `name`, `service_type`, `status`, timestamps) and changes the already-registered account’s `users.role`, `users.partner_id`, and `updated_at` in one transaction. The email is resolved to an existing customer account; the partner table itself has no email column. Admin partner tests passed locally. |
| Admin offers | Admin dashboard → `/api/admin/offers` | `AdminController` | Writes `offers` (title, destination, description, images, price fields, duration, rating/review count, highlights, active/featured/category/order and timestamps) and `offer_catalog_metadata` (`offer_id`, `badge`, `updated_at`) where applicable. |
| Admin monuments/places | Admin dashboard → `/api/admin/monuments` | `AdminController` | Writes `tourist_monuments` (title, location, categories, rating/review count, description, hours, visit timing, entry fee, image, tags, active/order and timestamps). |
| Admin attraction review decisions | Admin review action | `AdminController` | Uses `legacy_attraction_partner_reviews` to record reviewer, partner, decisions and mapped/omitted listing counts. **That table is missing in production**, so this history cannot be persisted there until the corresponding core migration is safely applied. |
| Push-token registration | `ApiService` → `/api/users/fcm-token` | `ApiController` and `zentrip_register_user_push_token` | Expected table: `user_push_tokens` (`token`, `user_id`, `platform`, `created_at`, `last_seen_at`). **The table is missing in production.** Push delivery is also disabled until Firebase configuration is supplied, so this path is not currently an active user feature. |
| Payment simulator | Checkout UI → `/api/payments/checkout`, `/api/payments/verify` | Authenticated simulated payment handlers | `payment_attempts` records `session_id`, user, amount, currency, `success`/`failed`, simulation flag, and an optional link to one booking/trip/transfer. No card details are stored. Booking APIs reject an explicitly supplied failed attempt; successful attempt IDs link transactionally. This remains a simulator, not a real charge. |

## 2. Data kept on the device rather than in Supabase

The following use `SharedPreferences` or in-memory state and do not have a server write path:

- Favorites/saved places.
- Price alerts and their local notifications; there is no server-side scheduled price monitor.
- Notification settings and notification history.
- Selected locale, currency, onboarding completion, and recent search/destination state.
- AI chat list/history cache used by the Flutter screen.
- Passenger passport/contact details during flight checkout. They are not sent to the backend, which is appropriate for the current scope.
- Payment-card details are not sent to the backend.

These values survive only according to device/app storage behavior; they do not synchronize across devices. The authentication token is also stored in `SharedPreferences`, rather than a platform secure-storage facility.

No changes were made to favorites, price alerts, notification settings/history, locale, or currency sync. Rough follow-up estimates: favorites persistence, 1–2 days; account-synced notification preferences/history, 1–2 days plus delivery setup; server-side price alerts, 2–4 days depending on provider polling limits; locale/currency sync, about 1 day. Estimates exclude production migration and release time.

### What database sync would require (deferred)

| Local feature | Likely table shape | API and screens to connect | Effort and constraints |
|---|---|---|---|
| Favorites / saved places | `user_favorites(user_id, item_type, item_id, created_at)` with an owner-scoped unique key and indexes by user and item | Authenticated list/add/remove endpoints; `FavoritesScreen`, profile count, and favorite buttons on place/offer cards | 1–2 days. First define stable IDs for provider-sourced places and offers so saved items survive provider refreshes. |
| Price alerts | `price_alerts(user_id, route_or_destination, target_price, currency, date_window, active, last_checked_at, last_notified_at, created_at)` | Owner-scoped CRUD endpoints; alert creation/list screens; a backend scheduled checker and notification delivery | 2–4 days plus provider polling design. Database storage alone does not monitor fares; polling must respect Duffel/provider quotas and alert de-duplication. |
| Notification preferences and history | `notification_preferences(user_id, category, enabled, updated_at)` plus `notification_events(user_id, type, payload, delivery_status, created_at, delivered_at)`; push tokens remain separate | Read/update preferences and list-history endpoints; notification settings and inbox/history screens | 1–2 days for persistence and UI wiring, plus Firebase client/Admin setup and delivery testing before notifications can be sent. |
| Locale and currency | `user_preferences(user_id, locale, currency, updated_at)` with one row per user | Read/update preference endpoints; language and currency screens; load after authentication and apply before formatting/rendering | About 1 day. Define how an account preference interacts with the current device selection and unauthenticated users. |

These are design notes only; no tables, endpoints, or UI changes for these device-local features were made.

## 3. Supabase schema comparison

The comparison used PostgreSQL catalog metadata and the checked-in base schema plus migrations. No production row contents were queried.

- The prior production metadata snapshot contains 21 public tables, 214 columns, 54 constraints, and 69 indexes. The checked-in base schema plus migrations now expects 28 application tables, plus `schema_migrations`. The legacy migration history has only a baseline record, so production state cannot be attributed to a verified migration sequence.

### Missing application tables

| Missing table | Expected columns | Affected path |
|---|---|---|
| `hotel_destinations` | `destination_type`, `destination_code`, `parent_code`, English/Arabic names and country names, country code, coordinates, `search_text`, `updated_at` | Hotel destination catalog lookup. The service falls back to popular cities/OpenTripMap when unavailable. There is no application writer or seed process for this table, so applying its DDL alone would still leave the catalog empty. |
| `landmark_places` | canonical/provider IDs, Wikidata ID, coordinates, category/rate, city/country, image, localized names/descriptions, provider payload, fetched/updated timestamps | Landmark cache and canonical place records. |
| `landmark_place_aliases` | canonical place ID, alias and normalized name, language, source, created timestamp | Landmark name matching/aliases. |
| `landmark_search_areas` | cache key, area/query/language/bounds, request/response payload, fetched/expiry timestamps | Cached landmark search areas. |
| `landmark_merge_candidates` | place IDs, distance/confidence/evidence, review status/timestamps | Duplicate-review workflow. |
| `legacy_attraction_partner_reviews` | partner/reviewer IDs, approval time, decisions, mapped/omitted counts | Admin attraction-partner retirement/review history. |
| `user_push_tokens` | token, user ID, platform, created/last-seen timestamps | Device push-token registration/removal. |
| `payment_attempts` | session ID, user ID, amount/currency, status, simulation flag, optional booking/trip/transfer link, timestamp | Simulated payment outcomes and transactional booking linkage. |

The application currently logs that the landmark catalog migration is absent and uses live OpenTripMap results. That fallback can return places, but it does not provide the missing persistent catalog/cache behavior.

### Other structural differences

- Production has one extra application-adjacent table, `flyway_schema_history`; it contains only the baseline record `1 / << Flyway Baseline >>`. Migration execution order cannot be proven from this history.
- Production has an extra nullable `users.auth_user_id UUID`, a unique index, and a foreign key to `auth.users(id) ON DELETE SET NULL`. The current Zentrip custom-session API does not use this field.
- No type, nullability, or default mismatch was found among same-named application columns.
- Production has additional foreign keys for partner/trip relationships and `offer_catalog_metadata.offer_id`; these are compatible with the current application.
- Production has additional search/GIN and lookup indexes, including offer/listing/monument search indexes and booking/trip/transfer partner-listing indexes.

The production-only application constraint names are `bookings_partner_id_foreign`, `bookings_trip_id_foreign`, `offer_catalog_metadata_offer_foreign`, `transfers_partner_id_foreign`, `transfers_partner_listing_id_foreign`, `trips_partner_id_foreign`, `trips_partner_listing_id_foreign`, and `users_auth_user_id_foreign`. `flyway_schema_history` also has its own primary-key constraint.

The production-only application index names are `api_tokens_expires_at_index`, `bookings_partner_listing_id_index`, `bookings_trip_id_index`, `flight_seat_holds_user_index`, `offers_highlights_gin`, `offers_location_trgm`, `offers_title_trgm`, `partner_listings_amenities_gin`, `tourist_monuments_loc_trgm`, `tourist_monuments_tags_gin`, `tourist_monuments_title_trgm`, `transfers_partner_listing_id_index`, `trips_partner_listing_id_index`, and `users_auth_user_id_key`, in addition to indexes for `flyway_schema_history`. No definition mismatch was found for common constraints or indexes with the same name.

### Migration state

The source migration order is:

1. `20261101_schema_migrations.sql` — new private ledger; not present in the prior production snapshot.
2. `20261101_global_airport_directory.sql` — airport columns/indexes were present in the prior production snapshot, but Flyway baseline history cannot prove how they were applied.
3. `20261101_role_access_rls.sql` — many core role policies exist, but the prior live policy set was not identical to the checked-in migration. Treat this as a one-time baseline and do not replay it.
4. `20261102_landmark_catalog.sql` — the prior snapshot lacked all four catalog tables; local migration now creates them idempotently.
5. `20261103_hotel_destination_catalog.sql` — the prior snapshot lacked `hotel_destinations`; local migration now creates it with backend-only access.
6. `20261104_core_data_rls.sql` — local migration creates the missing legacy review table and hardens visit-table RLS/permissions. Production remains unchanged.
7. `20261104_payment_attempts.sql` — new simulator ledger migration; not applied to production.
8. `20261105_user_push_tokens.sql` — the prior snapshot lacked `user_push_tokens`; local migration creates it with owner-scoped runtime policies.

The prior production statuses are inferred from schema objects, not a trustworthy migration ledger. Do not treat the first two as proven-applied versions.

## 4. RLS and permissions

- Production contains 46 public-schema policies. Several names differ from the current migration set; 18 expected policy names are absent. Some of those apply to the missing tables. For existing tables, the missing names include runtime policies for password reset, user registration/auth lookup, token insertion, partner transfer-schedule reads, and partner profile reads.
- Production also has six policies not named in the current migrations (`airports_public_read`, `offer_catalog_metadata_public_read`, `offers_public_read`, `tourist_monuments_public_read`, `user_reviews_public_read`, and `users_self_read`). Their presence is part of the schema drift; review their definitions before replacing or removing them.
- The 18 expected names absent from production are `hotel_destinations_public_read`, `hotel_destinations_runtime_manage`, `user_push_tokens_owner_delete`, `user_push_tokens_owner_read`, `zentrip_api_tokens_authenticated_insert`, `zentrip_attraction_visit_counts_runtime`, `zentrip_attraction_visit_dedup_runtime`, `zentrip_landmark_aliases_runtime`, `zentrip_landmark_merge_candidates_runtime`, `zentrip_landmark_places_runtime`, `zentrip_landmark_search_areas_runtime`, `zentrip_legacy_attraction_reviews_admin`, `zentrip_password_reset_codes_email`, `zentrip_transfer_schedules_partner_read`, `zentrip_user_profiles_partner_self_read`, `zentrip_users_auth_email_lookup`, `zentrip_users_password_reset_update`, and `zentrip_users_registration_insert`.
- The prior production snapshot had RLS disabled on `attraction_visit_counts` and `attraction_visit_dedup`, with direct `anon`/`authenticated` `SELECT` and `INSERT`. This remains a production issue until the local `20261104_core_data_rls.sql` migration is applied and verified there.
- Local PostgreSQL tests now assert that `anon` and `authenticated` have no direct `SELECT`, `INSERT`, or `UPDATE` privileges on either visit table, while the backend visit API still passes its dedupe/rollup tests.
- The backend database login is `BYPASSRLS`; authenticated application queries are intended to switch to the `zentrip_api_runtime` role inside a transaction and set transaction-local identity context. Do not test RLS using the bypass role alone.

## 5. Migrations and safe manual steps

The prior live migration history is insufficient to establish a reliable applied sequence. Do not rerun `schema.sql` as a reset and do not blindly replay the role migration.

Before changing production:

1. Take a full Supabase backup and confirm the restore path before opening SQL Editor.
2. Run the read-only inspection query below. Compare columns, indexes, RLS, policies, grants, runtime role, and helper functions; do not use Flyway’s baseline row as proof.
3. Apply `20261101_schema_migrations.sql`. Later feature migrations record their own versions.
4. Apply the airport migration only if its columns/indexes are absent. For an already-present object, add its version to the ledger only after verifying the full expected definition.
5. Do not replay `20261101_role_access_rls.sql` against the existing production policy set. Confirm `zentrip_api_runtime` and its three RLS helper functions first. The prior audit found policy differences; reconcile them separately before recording a baseline version.
6. After review of production-specific policies, apply only missing feature migrations in order: landmark catalog, hotel destination catalog, core data/RLS, payment attempts, then user push tokens. Each SQL file is under `backend/src/main/resources/migrations/`.
7. Verify the visit tables have RLS enabled and no direct anon/authenticated read/insert/update grants, then test the API under `zentrip_api_runtime` with disposable data. Verify payment-attempt ownership and link constraints.
8. `hotel_destinations` is only a cache/catalog table; applying its DDL does not seed rows. Verify the existing fallback or plan a separate managed import before relying on catalog suggestions.

Read-only Supabase metadata query:

```sql
SELECT t.table_name,
       c.relrowsecurity AS rls_enabled,
       cols.column_definitions,
       pol.policy_definitions
FROM information_schema.tables t
JOIN pg_class c ON c.oid = to_regclass(format('%I.%I', t.table_schema, t.table_name))
LEFT JOIN LATERAL (
    SELECT string_agg(format('%I %s%s', column_name, data_type,
           CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END),
           E'\n' ORDER BY ordinal_position) AS column_definitions
    FROM information_schema.columns
    WHERE table_schema = t.table_schema AND table_name = t.table_name
) cols ON TRUE
LEFT JOIN LATERAL (
    SELECT string_agg(format('%I roles=%s command=%s using=%s check=%s',
           policyname, roles, cmd, coalesce(qual, ''), coalesce(with_check, '')),
           E'\n' ORDER BY policyname) AS policy_definitions
    FROM pg_policies
    WHERE schemaname = t.table_schema AND tablename = t.table_name
) pol ON TRUE
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name;

WITH expected(table_name) AS (
    VALUES ('attraction_visit_counts'),
           ('attraction_visit_dedup'),
           ('schema_migrations'),
           ('hotel_destinations'),
           ('landmark_places'),
           ('landmark_place_aliases'),
           ('landmark_search_areas'),
           ('landmark_merge_candidates'),
           ('legacy_attraction_partner_reviews'),
           ('user_push_tokens'),
           ('payment_attempts')
)
SELECT roles.role_name,
       expected.table_name,
       to_regclass(format('public.%I', expected.table_name)) IS NOT NULL AS table_exists,
       CASE WHEN to_regclass(format('public.%I', expected.table_name)) IS NULL THEN NULL
            ELSE has_table_privilege(
                roles.role_name, format('public.%I', expected.table_name), 'SELECT')
       END AS can_select,
       CASE WHEN to_regclass(format('public.%I', expected.table_name)) IS NULL THEN NULL
            ELSE has_table_privilege(
                roles.role_name, format('public.%I', expected.table_name), 'INSERT')
       END AS can_insert,
       CASE WHEN to_regclass(format('public.%I', expected.table_name)) IS NULL THEN NULL
            ELSE has_table_privilege(
                roles.role_name, format('public.%I', expected.table_name), 'UPDATE')
       END AS can_update
FROM (VALUES ('anon'), ('authenticated')) AS roles(role_name)
CROSS JOIN expected
ORDER BY expected.table_name, roles.role_name;

SELECT version, name, applied_at
FROM public.schema_migrations
ORDER BY version;
```

The final query is valid only after `schema_migrations` exists. No migrations were applied to Supabase during this work.

## 6. Test results and boundaries

| Check | Result |
|---|---|
| Live Supabase connection | Connected using configured environment secrets; read-only catalog metadata only. No secret values were printed. |
| PostgreSQL migration/backend suite | `bash scripts/test-postgres.sh`: 230 tests passed, 0 failures, 0 errors, 0 skipped. `PostgresMigrationIntegrationTest` ran 34 tests against a fresh temporary loopback-only PostgreSQL database after applying the full migration chain. |
| Flutter static analysis | `.local/toolchains/flutter/bin/flutter analyze`: no issues found in this verification. |
| Flutter tests | `.local/toolchains/flutter/bin/flutter test`: 177 tests passed, including transfer history and Duffel seat/extras coverage. |
| Flutter web build | Previously passed; not rerun in this verification because only database tests/docs changed. |
| Backend package build | The full Maven test run compiled and tested the backend. No separate package build was run in this verification. |
| CI | `.github/workflows/backend-postgres.yml` already runs `bash scripts/test-postgres.sh` on pushes and pull requests; no CI workflow change was needed. |
| Live Supabase schema/data check | Not run during this implementation. The previously captured metadata still requires manual revalidation before applying SQL. |
| Live authenticated booking/UI test | Not run. No production test account was created and no production booking/profile rows were written. |
| Test data | The PostgreSQL suite used synthetic fixtures in a temporary local database; the script stopped and removed that database. No Supabase test data was created or removed. |

The tests verify that the checked-in schema/migration chain works on a fresh local PostgreSQL database. They do **not** prove that a production booking currently exists, that a live customer can complete checkout, or that the current Supabase database has the same migration state. The production visit-table exposure remains open until the owner applies and verifies the migration.

## 7. Findings and status

“Fixed locally” means code and disposable-PostgreSQL tests pass. It does **not** mean the external Supabase project was changed. “Needs manual Supabase step” stays open until the owner backs up, reviews the current schema/policies, applies only approved missing SQL, and reruns the verification query there.

| Finding | Local status | Supabase / product status |
|---|---|---|
| Visit-count tables allow direct public-role access in the prior production snapshot | **Fixed locally** | **Needs manual Supabase step**: apply the reviewed visit-table permission change and prove direct `anon`/`authenticated` access is denied after deployment. |
| Migration history cannot be inferred from the prior Flyway baseline | **Fixed locally**: private `schema_migrations` ledger and ordered local chain | **Needs manual Supabase step**: establish the ledger only after comparing actual object definitions and confirming which migrations are safe to record. |
| Seven previously missing feature tables (hotel destination catalog, four landmark tables, legacy attraction review history, push tokens) | **Fixed locally**: additive/idempotent migrations and permission tests | **Needs manual Supabase step**: inspect and apply only missing tables/policies. The hotel catalog migration does not seed destination rows. |
| Transfer history in My Trips | **Fixed locally**: authenticated transfer loading and widget test | Requires release; no production transfer rows were read or written. |
| Duffel seat and extras persistence/display | **Fixed locally**: existing trip `details` storage, confirmation/ticket, My Trips, and PostgreSQL round-trip test | Requires release; no production trip was modified. |
| Simulator payment-attempt ledger | **Fixed locally**: success/failure persistence, owner RLS, and failed-attempt booking rejection test | **Needs manual Supabase step** before release. It records only simulated outcomes; no card data or real charge is stored. |
| Favorites, price alerts, notification settings/history, locale, currency | **Open by design**: remain device-local | Deferred; design, tables, endpoints, screens, and effort are listed above. |
| AI chat persistence can fail while the stream reports completion | **Open** | No change made in this scope. |
| Profile/partner images are stored on server-local disk | **Open** | No change made in this scope; durable object storage would be a separate project. |
| Push delivery is disabled until Firebase is configured | **Open** | Token persistence is prepared locally; delivery setup remains a manual provider/configuration step. |
| Supabase-specific columns, constraints, extra policies, and role membership from the prior snapshot | **Open pending current inspection** | **Needs manual Supabase step**: rerun the read-only metadata query before any migration; the previous snapshot is not current proof. |

### Findings by severity

### High

1. **Public direct access to attraction visit tables in production.** The prior metadata snapshot showed RLS disabled and direct `anon`/`authenticated` read/insert grants. Local migration/tests now address this, but production still needs the reviewed migration and post-apply verification.
2. **Production migration state is not auditable from Flyway.** Only a baseline is recorded while seven expected tables are absent and policy state differs. Production writes to affected routes cannot be considered fully verified.
3. **Migration history is not yet reconciled in production.** The new tracker is local code only; the existing Flyway baseline is insufficient to establish which migrations were applied.

### Medium

4. **Landmark catalog persistence is unavailable in production.** The UI uses live provider fallback, but cache, aliases, and deduplication tables are missing.
5. **Admin attraction review history cannot persist.** Its production table is missing.
6. **Push token endpoints cannot persist tokens in production.** The table is missing; push delivery is currently disabled.
7. **Hotel destination catalog is both absent and unpopulated by application code.** The fallback is available, but the database catalog will not populate merely by applying its migration.
8. **AI response persistence is best-effort while the stream reports completion.** Database write errors are logged but do not change the successful `done` event.
9. **Duffel flight seat/extras now persist in local code and are covered by a PostgreSQL regression test.** Production needs the release and schema changes before it can use the path.
10. **Uploaded profile/partner images are stored on local server disk.** Database URLs do not guarantee that image files survive server replacement or redeployment.
11. **Several user preferences and saved features are device-local.** They do not synchronize across devices; price alerts are not backed by a server-side monitor.

### Low / intentional scope

12. **Payments remain simulations.** The local payment-attempt ledger records simulator outcomes but does not capture money and must not be presented as a real payment processor.
13. **Passenger identity and card details are transient/not sent to the database.** This is a privacy-preserving boundary in the current implementation.
14. **Production has a Supabase Auth `users.auth_user_id` extension not used by the current custom-session API.** It is nullable and does not conflict with the matched application columns, but should remain documented until the auth model is intentionally changed.

## 8. Local fixes applied

- Added a migration ledger and dependency checks; applied the complete chain locally against a temporary PostgreSQL cluster with all seven previously missing feature tables dropped first.
- Added a migration for simulator-only payment attempts. Success/failure is user-scoped, contains no card data, and successful attempts link transactionally to one booking, trip, or transfer.
- Revoked direct anon/authenticated access to visit counters and deduplication rows while preserving runtime-role API access.
- Added transfer loading/filter/details to My Trips and persisted Duffel selected seats/extras through the existing `trips` storage path.
- Added regression tests for migration idempotency, missing dependencies/tables, direct grants on visit/private tables, payment owner isolation and failed-payment booking rejection, push-token owner isolation, transfer history, and saved Duffel selections.

**Production status:** These are source-code and local-test changes only. Supabase still requires a backup, the read-only metadata check above, an owner-reviewed application of the missing SQL, and post-migration permission tests. Do not mark production issues resolved until those steps are completed.
