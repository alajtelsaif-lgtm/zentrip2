# Zentrip database persistence verification

**Verification date:** 2026-11-04  
**Scope:** Flutter-to-API persistence paths, PostgreSQL/Supabase schema alignment, RLS, and local PostgreSQL test coverage.  
**Production safety:** Supabase was accessed for schema metadata only. No customer rows were queried, and no production rows, schema, migrations, or accounts were changed.

## Executive summary

The core account, flight, hotel, car, package, attraction, transfer, preference, review, partner-listing, offer, and monument write paths exist. A fresh local PostgreSQL instance passed the migration and backend tests, and the Flutter checks passed.

The live Supabase schema is **not fully aligned** with the current migrations:

- It has 21 public tables, including `flyway_schema_history`; the current schema plus migrations expects 27 application tables.
- Seven expected application tables are missing: `hotel_destinations`, four landmark catalog tables, `legacy_attraction_partner_reviews`, and `user_push_tokens`.
- `attraction_visit_counts` and `attraction_visit_dedup` have RLS disabled in Supabase. The `anon` and `authenticated` roles also have direct table `SELECT` and `INSERT` privileges. This bypasses the application endpoint’s visit limits and is the highest-priority issue.
- `flyway_schema_history` contains only a baseline row, so it does not establish which SQL migrations ran or in what order.
- Transfers are persisted by the API but are not loaded by the Flutter My Trips controller.
- Favorites, price alerts, notification preferences, locale, and currency are device-local, not Supabase-synced.
- The app’s payment flow is explicitly simulated. It does not create a payment record or prove that money was captured.

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
| Attraction visit count | Attraction screen → `/api/attractions/{id}/visits` | `ApiController` visit handler | Inserts into `attraction_visit_dedup` (`attraction_id`, `visitor_hash`, `counted_at`) and increments `attraction_visit_counts` (`attraction_id`, `visit_count`). Deduplication/rollup passed local PostgreSQL tests. Live RLS protection is currently missing; see findings. |
| Partner flight booking | Flight checkout → `/api/bookings/confirm` | `ApiController` transactional confirmation | Creates a `trips` row (`user_id`, flight route/date fields, airline/flight, class, price, `booking_ref`, status, `details`) and confirms the matching `flight_seat_holds` (`flight_listing_id`, `seat_number`, `user_id`, `trip_id`, status, `booking_ref`, expiry/timestamps). `details` includes selected seats and extras. Local tests cover inventory reservation, rollback, cancellation, and customer isolation. |
| Duffel flight booking | Flight checkout → `/api/trips` | `ApiController` trip creation | Creates a `trips` row with route, dates, flight, class, price, reference, passenger count and provider metadata in `details` (`source`, offer ID, currency, `is_simulated`). The UI’s selected seat numbers and extras are not passed in the `TripModel` used for this write, so they are not recoverable from the saved Duffel trip after the in-memory confirmation screen is gone. |
| Hotel, car, package, attraction booking | Detail/checkout screens → `/api/bookings` | `ApiController` booking creation and inventory service | Creates `bookings` (`user_id`, `partner_id`, `partner_listing_id`, `trip_id`, `type`, `status`, `total_amount`, `title`, `subtitle`, `date`, `price`, `ref_code`, `details`, timestamps). `details` currently includes supported values such as end date, image URL, room count/reservation flag, and vehicle reservation flag. Reservation changes are transactional; local tests cover hotel/car booking, cancellation, and inventory rollback. For external hotel results, the persisted summary does not include a LiteAPI hotel/offer ID or a durable provider reference. |
| Transfer booking | Transfer checkout → `/api/transfers` | `ApiController` transfer creation | Transactionally inserts `transfers` (`user_id`, `partner_id`, `partner_listing_id`, provider, vehicle, pickup/dropoff, time, price, passengers, status, timestamps) and `transfer_schedules` (`transfer_id`, `duration_minutes`). PostgreSQL test confirmed both records are created. **The My Trips controller loads `/api/trips` and `/api/bookings`, but not `/api/transfers`, so saved transfers are absent from that screen.** |
| Partner listing management | Partner dashboard → `/api/partner/listings` | `PartnerController` | Creates/updates/delists `partner_listings`: partner ID, type, title, city/country, description, image URL, price/active state, JSON attributes, hotel location/map/place/rating/review/amenity/tax/room fields, timestamps. Queries scope mutations by the authenticated partner ID. Listing creation and role-isolation tests passed locally. Uploaded image files are local disk files, not object storage. |
| Admin partner management | Admin dashboard → `/api/admin/partners` | `AdminController` | Creates `partners` (`slug`, `name`, `service_type`, `status`, timestamps) and changes the already-registered account’s `users.role`, `users.partner_id`, and `updated_at` in one transaction. The email is resolved to an existing customer account; the partner table itself has no email column. Admin partner tests passed locally. |
| Admin offers | Admin dashboard → `/api/admin/offers` | `AdminController` | Writes `offers` (title, destination, description, images, price fields, duration, rating/review count, highlights, active/featured/category/order and timestamps) and `offer_catalog_metadata` (`offer_id`, `badge`, `updated_at`) where applicable. |
| Admin monuments/places | Admin dashboard → `/api/admin/monuments` | `AdminController` | Writes `tourist_monuments` (title, location, categories, rating/review count, description, hours, visit timing, entry fee, image, tags, active/order and timestamps). |
| Admin attraction review decisions | Admin review action | `AdminController` | Uses `legacy_attraction_partner_reviews` to record reviewer, partner, decisions and mapped/omitted listing counts. **That table is missing in production**, so this history cannot be persisted there until the corresponding core migration is safely applied. |
| Push-token registration | `ApiService` → `/api/users/fcm-token` | `ApiController` and `zentrip_register_user_push_token` | Expected table: `user_push_tokens` (`token`, `user_id`, `platform`, `created_at`, `last_seen_at`). **The table is missing in production.** Push delivery is also disabled until Firebase configuration is supplied, so this path is not currently an active user feature. |
| Payment simulator | Checkout UI → `/api/payments/checkout`, `/api/payments/verify` | Mock payment handlers | No payment/transaction table is written. The API returns a simulated checkout and verification result. A booking is only created after the simulator returns success, but the database does not record a payment status or captured transaction. This must not be represented as a real charge. |

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

## 3. Supabase schema comparison

The comparison used PostgreSQL catalog metadata and the checked-in base schema plus migrations. No production row contents were queried.

- Production metadata contains 21 public tables, 214 columns, 54 constraints, and 69 indexes. The checked-in base schema plus migrations expects 27 application tables. The migration history has only the baseline record, so the current production state cannot be attributed to a verified migration sequence.

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

1. `20261101_global_airport_directory.sql` — airport columns and lookup indexes are present in production; the baseline-only history prevents confirming when/how it was applied.
2. `20261101_role_access_rls.sql` — many core role policies exist, but the live policy set is not identical to the checked-in migration set.
3. `20261102_landmark_catalog.sql` — pending in production; all four landmark catalog tables are absent.
4. `20261103_hotel_destination_catalog.sql` — pending in production; `hotel_destinations` is absent.
5. `20261104_core_data_rls.sql` — production is inconsistent with the current file: the legacy review table is absent and the visit tables do not have the expected RLS state/policies.
6. `20261105_user_push_tokens.sql` — pending in production; `user_push_tokens` is absent.

These statuses are inferred from schema objects, not a trustworthy migration ledger. Do not treat the first two as proven-applied versions.

## 4. RLS and permissions

- Production contains 46 public-schema policies. Several names differ from the current migration set; 18 expected policy names are absent. Some of those apply to the missing tables. For existing tables, the missing names include runtime policies for password reset, user registration/auth lookup, token insertion, partner transfer-schedule reads, and partner profile reads.
- Production also has six policies not named in the current migrations (`airports_public_read`, `offer_catalog_metadata_public_read`, `offers_public_read`, `tourist_monuments_public_read`, `user_reviews_public_read`, and `users_self_read`). Their presence is part of the schema drift; review their definitions before replacing or removing them.
- The 18 expected names absent from production are `hotel_destinations_public_read`, `hotel_destinations_runtime_manage`, `user_push_tokens_owner_delete`, `user_push_tokens_owner_read`, `zentrip_api_tokens_authenticated_insert`, `zentrip_attraction_visit_counts_runtime`, `zentrip_attraction_visit_dedup_runtime`, `zentrip_landmark_aliases_runtime`, `zentrip_landmark_merge_candidates_runtime`, `zentrip_landmark_places_runtime`, `zentrip_landmark_search_areas_runtime`, `zentrip_legacy_attraction_reviews_admin`, `zentrip_password_reset_codes_email`, `zentrip_transfer_schedules_partner_read`, `zentrip_user_profiles_partner_self_read`, `zentrip_users_auth_email_lookup`, `zentrip_users_password_reset_update`, and `zentrip_users_registration_insert`.
- RLS is disabled on `attraction_visit_counts` and `attraction_visit_dedup`; the current local migration expects it enabled.
- Read-only privilege checks confirmed `anon` and `authenticated` have table `SELECT` and `INSERT` privileges on both visit tables. Direct Supabase/PostgREST requests can therefore bypass the API’s visit limit/dedup logic. The same tables should be protected by RLS with access limited to the backend runtime role, as intended by `20261104_core_data_rls.sql`.
- The backend database login is `BYPASSRLS`; authenticated application queries are intended to switch to the `zentrip_api_runtime` role inside a transaction and set transaction-local identity context. Do not test RLS using the bypass role alone.

## 5. Migrations and safe manual steps

The live migration history is insufficient to establish a reliable applied sequence. Schema state indicates the airport directory and many role policies exist, while the missing tables and visit-table RLS state above do not match the current source migrations. Do not rerun `schema.sql` as a reset and do not blindly replay the role migration.

Before changing production:

1. Take a Supabase backup and keep it available for rollback.
2. As a database owner, compare the current objects against the migrations; do not infer migration completion from the baseline-only Flyway row.
3. Review and apply only missing DDL from `20261102_landmark_catalog.sql`, `20261103_hotel_destination_catalog.sql`, `20261104_core_data_rls.sql`, and `20261105_user_push_tokens.sql`. `20261104_core_data_rls.sql` is the source for enabling RLS on the two visit tables and adding the missing policies; inspect its effects against production’s extra policies before applying.
4. Confirm `zentrip_api_runtime` remains `NOLOGIN` and `NOBYPASSRLS`, the JDBC login can `SET ROLE` to it, and the role can perform the required application operations under the intended RLS context.
5. Verify both visit tables have RLS enabled, no direct `anon`/`authenticated` insert/select grants, and runtime-only access. Then run read/write/isolation probes using disposable test rows and remove them.
6. If installing `hotel_destinations`, add an owned, repeatable catalog import/refresh process and verify data exists; the application currently has no writer for it.

No migrations were applied during this verification.

## 6. Test results and boundaries

| Check | Result |
|---|---|
| Live Supabase connection | Connected using configured environment secrets; read-only catalog metadata only. No secret values were printed. |
| PostgreSQL migration/backend suite | `bash scripts/test-postgres.sh`: 224 tests passed, 0 failures, 0 errors, 0 skipped. This includes 29 PostgreSQL migration integration tests on a temporary loopback-only PostgreSQL cluster. |
| Flutter static analysis | `.local/toolchains/flutter/bin/flutter analyze`: no issues found. |
| Flutter tests | `.local/toolchains/flutter/bin/flutter test`: 168 tests passed. |
| Live authenticated UI/write-flow test | Not run. No production test account was created and no production booking/profile rows were written. |
| Test data | The PostgreSQL suite used synthetic fixtures in a temporary local database; the script stopped and removed that database. No Supabase test data was created or removed. |

The tests verify that the checked-in schema/migration chain works on a fresh local PostgreSQL database. They do **not** prove that a production booking currently exists, that a live customer can complete checkout, or that the current Supabase database has the same migration state.

## 7. Findings by severity

### High

1. **Public direct access to attraction visit tables.** RLS is disabled, and `anon`/`authenticated` can select and insert. This allows direct access around API throttling and deduplication. Apply and verify the intended RLS policy before relying on visit counts.
2. **Production migration state is not auditable from Flyway.** Only a baseline is recorded while seven expected tables are absent and policy state differs. Production writes to affected routes cannot be considered fully verified.
3. **Transfers disappear from My Trips.** The API persists them, but the Flutter controller does not request `/api/transfers`.

### Medium

4. **Landmark catalog persistence is unavailable in production.** The UI uses live provider fallback, but cache, aliases, and deduplication tables are missing.
5. **Admin attraction review history cannot persist.** Its production table is missing.
6. **Push token endpoints cannot persist tokens in production.** The table is missing; push delivery is currently disabled.
7. **Hotel destination catalog is both absent and unpopulated by application code.** The fallback is available, but the database catalog will not populate merely by applying its migration.
8. **AI response persistence is best-effort while the stream reports completion.** Database write errors are logged but do not change the successful `done` event.
9. **Duffel flight seat/extras are not included in the persisted trip.** The confirmation UI holds them only in memory.
10. **Uploaded profile/partner images are stored on local server disk.** Database URLs do not guarantee that image files survive server replacement or redeployment.
11. **Several user preferences and saved features are device-local.** They do not synchronize across devices; price alerts are not backed by a server-side monitor.

### Low / intentional scope

12. **Payments are simulations, not persisted transactions.** No payment ledger or captured-payment status exists. This is acceptable for a simulator but not for real-money booking.
13. **Passenger identity and card details are transient/not sent to the database.** This is a privacy-preserving boundary in the current implementation.
14. **Production has a Supabase Auth `users.auth_user_id` extension not used by the current custom-session API.** It is nullable and does not conflict with the matched application columns, but should remain documented until the auth model is intentionally changed.

## 8. Safe fixes applied

None. This verification found production schema and access issues that require a reviewed migration, plus product decisions about device-local data and booking history. No production or application behavior was changed without first reporting those findings.
