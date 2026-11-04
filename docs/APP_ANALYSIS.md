# Zentrip Application Audit

**Audit date:** 2026-11-04  
**Scope:** Read-only review of the Flutter client, Spring Boot API, database schema/migrations, external integrations, security boundaries, and available tests. No application source code was changed for this audit; this report is the only audit deliverable.

## Executive summary

Zentrip is a Flutter travel app backed by a Spring Boot API and PostgreSQL hosted through Supabase. The project has a broad feature set, role-based API authorization, a usable test suite, and working development startup. Flight and hotel search combine external data with partner inventory, while checkout remains simulated.

The main blockers are not general startup failures. They are specific API-contract and database-security gaps:

1. The role/RLS migration creates PostgreSQL policies but does not enable row-level security on the existing core tables. The local PostgreSQL test script does not apply that migration, so the tests do not verify those policies.
2. Several Flutter service methods call endpoints that have no matching backend route and are rejected by the API's default-deny rule.
3. The implemented nearby-attractions endpoint is also omitted from the security allowlist and is therefore inaccessible even to customers.
4. Duffel and LiteAPI provide search data only. No provider order-creation integration is present, and the checkout endpoint returns a mock payment session.
5. The default CORS configuration permits any origin, and the OpenTripMap configuration/logging indicates a free-plan versus commercial-use mismatch that needs a licensing decision.

The development server starts and the code-level test suites pass. This does not establish that live provider credentials are valid, that production Supabase has every migration applied, or that authenticated screens work against production data.

## Architecture and feature flow

### Application structure

- **Client:** Flutter/Dart, organized by feature (auth, home, trips, flight booking, hotel booking, cars, transfers, attractions, nearby/maps, chatbot, profile, admin, and partner).
- **Client state/networking:** Feature controllers call a shared Dio-based `ApiService`; models normalize API responses. English and Arabic localization files are present, and the app supports RTL.
- **Backend:** Spring Boot 3.5.6 on Java 25. Controllers expose the `/api` contract; services call external providers; JDBC/JPA connect to PostgreSQL.
- **Database:** PostgreSQL through Supabase connection settings. The Flutter code does not use Supabase as its application data API; database access is through the backend. `supabase_flutter` is declared in `pubspec.yaml`, but no application source use of `Supabase.instance` was found.
- **Authentication:** The backend issues bearer tokens and stores their SHA-256 hashes in `api_tokens`. `TokenAuthFilter` looks up the token and loads the current role and partner ID from `users`; it does not trust a role from the request body. The Flutter client persists its bearer token in `SharedPreferences`.
- **Web/API address:** Flutter web uses relative `/api`; Android emulator builds default to `http://10.0.2.2:8080/api`; other non-web targets default to loopback unless `ZENTRIP_API_URL` is supplied.

### Major user journeys

| Journey | Current flow | Audit status |
|---|---|---|
| Sign-in and account recovery | Flutter auth screens → `/auth/*` → `users`, `password_reset_codes`, `api_tokens` | Backend routes exist. Social sign-in is called by Flutter but has no corresponding backend route. Mail delivery depends on SMTP configuration. |
| Flight search | Flight search UI → regular/flexible partner search → partner listings plus Duffel offer requests → normalized Flutter flight models | Search integration exists. Duffel is search-only; it does not create an airline order. |
| Flight booking | Fare/passenger/seat/review screens → seat holds and local trip/booking confirmation → mock payment path | Local Zentrip records can be created for supported partner flows. The project does not submit an order to Duffel or a card payment to a processor. |
| Hotel search | Destination catalog/autocomplete → LiteAPI rates plus partner inventory → normalized hotel results and details | Search/data integration exists. LiteAPI is read-only in Zentrip; booking uses the simulated partner flow. |
| My Trips/history | Customer token → `/trips` and `/bookings` → Flutter merges the two sources | The existing tests cover merged data and error refresh behavior. The endpoint returns are not paginated. |
| Tourist places | Flutter search/map → OpenTripMap, Geoapify geocoding where needed, landmark catalog/cache | Live provider and persistent-cache paths exist. `/attractions/nearby` is blocked by the API security allowlist. |
| AI assistant | Chat screen → authenticated `/ai/chat` SSE stream → Requesty | Backend streaming integration exists; the live provider/account was not tested. |
| Admin/partner management | Client route guard → role-protected `/admin/**` or `/partner/**` endpoints | Both client and server checks exist. PostgreSQL RLS enforcement has a migration gap described below. |
| Car rental and transfers search | Car/transfers screens → `ApiService` search methods | The client paths do not match a backend search route; these searches are not fully wired. |

### Screen and navigation inventory

The named route generator includes splash, onboarding, login/register/recovery/verification, home, trip details, flight search/results/booking, hotel search/results/detail, car search/detail, attractions/detail, package list/detail, transfers, terms/privacy, and admin/partner dashboards. Feature folders also include nearby/map, favorites, chat/history, profile/settings, itinerary/My Trips, and the fare/passenger/seat/review/payment/confirmation stages.

The customer shell has Home/Explore, Nearby, Zen AI, My Trips, and Profile navigation. Admin and partner accounts are redirected to their own dashboard by the client route generator; server authorization is the actual security boundary. A direct unauthenticated navigation to a non-dashboard Flutter route is not uniformly blocked by the route generator, so those screens must continue to rely on authenticated API responses.

## Backend endpoint and access matrix

Roles below describe the Spring Security rule currently applied. “Public” means no authenticated role is required. Unmatched `/api/**` paths are denied.

### Public and authentication endpoints

| Method and path | Allowed role(s) |
|---|---|
| `POST /api/auth/register` | Public |
| `POST /api/auth/login` | Public |
| `POST /api/auth/forgot-password` | Public |
| `POST /api/auth/verify-code` | Public |
| `POST /api/auth/reset-password` | Public |
| `GET /api/auth/me` | Any authenticated role |
| `POST /api/auth/logout` | Any authenticated role |
| `POST /api/attractions/{id}/visits` | Public, with application-level burst limiting |
| `GET /api/reviews` | Public |
| `POST /api/reviews` | Customer |
| `GET /api/offers` | Public |
| `GET /api/airports/search` | Public |
| `GET /api/flights/search` | Public |
| `GET /api/flights/search/flexible` | Public |
| `GET /api/hotels/locations` | Public |
| `GET /api/hotels/destinations/suggest` | Public |
| `GET /api/hotels/search` | Public |
| `GET /api/hotels/nearby` | Public |
| `GET /api/cars/locations` | Public |
| `GET /api/cars/nearby` | Public |
| `GET /api/inventory/{type}` | Public |
| `GET /api/attractions/search` | Public |
| `GET /api/attractions/suggestions` | Public |
| `GET /api/attractions/map` | Public |
| `GET /api/attractions/recent-destination` | Public |
| `GET /api/exchange-rates` | Public |

### Customer endpoints

| Method and path | Allowed role(s) |
|---|---|
| `POST /api/profile` | Customer |
| `PUT /api/profile/password` | Customer |
| `GET /api/preferences/travel` | Customer |
| `PUT /api/preferences/travel` | Customer |
| `GET /api/trips` | Customer |
| `POST /api/trips` | Customer |
| `GET /api/trips/availability` | Customer |
| `DELETE /api/trips/{id}` | Customer |
| `GET /api/flights/{flightId}/seats` | Customer |
| `POST /api/flights/{flightId}/seats/reserve` | Customer |
| `DELETE /api/flights/{flightId}/seats/reserve` | Customer |
| `POST /api/bookings/confirm` | Customer |
| `GET /api/bookings` | Customer |
| `GET /api/bookings/availability` | Customer |
| `POST /api/bookings` | Customer |
| `DELETE /api/bookings/{id}` | Customer |
| `GET /api/transfers` | Customer |
| `GET /api/transfers/availability` | Customer |
| `POST /api/transfers` | Customer |
| `POST /api/payments/checkout` | Customer |
| `GET /api/payments/verify/{sessionId}` | Customer |
| `GET /api/maps/search` | Customer |
| `POST /api/ai/chat` | Customer |
| `POST /api/ai/chat/cancel` | Customer |

### Partner endpoints

All routes below are restricted to `PARTNER` by `/api/partner/**`.

| Method and path |
|---|
| `POST /api/partner/hotel-images` |
| `GET /api/partner/dashboard` |
| `GET /api/partner/listings` |
| `POST /api/partner/listings` |
| `PUT /api/partner/listings/{id}` |
| `DELETE /api/partner/listings/{id}` |
| `GET /api/partner/reservations` |
| `GET /api/partner/customers` |

### Admin endpoints

All routes below are restricted to `ADMIN` by `/api/admin/**`.

| Method and path |
|---|
| `GET /api/admin/dashboard` |
| `GET /api/admin/attractions/popularity` |
| `GET /api/admin/partners` |
| `GET /api/admin/partners/legacy-attractions` |
| `POST /api/admin/partners/{id}/attraction-review` |
| `POST /api/admin/partners` |
| `DELETE /api/admin/partners/{id}` |
| `POST /api/admin/partners/{id}/activate` |
| `GET /api/admin/reservations` |
| `GET /api/admin/customers` |
| `GET /api/admin/monuments` |
| `POST /api/admin/monuments` |
| `PUT /api/admin/monuments/{id}` |
| `DELETE /api/admin/monuments/{id}` |
| `GET /api/admin/offers` |
| `POST /api/admin/offers` |
| `PUT /api/admin/offers/{id}` |
| `DELETE /api/admin/offers/{id}` |

### Implemented or called paths with access/contract problems

| Client/server path | Finding |
|---|---|
| `GET /api/attractions/nearby` | A backend handler and Flutter service method exist, but the path is absent from the security allowlist. It falls through to `denyAll`, so an authenticated customer receives 403. |
| `POST /api/auth/social-login` | Called by Google and Apple auth controller methods; no backend mapping exists and the path is denied by default. |
| `GET /api/destinations/weather` | Called by package detail; no backend mapping exists and it is denied by default. |
| `GET /api/destinations/visa-info` | Called by package detail; no backend mapping exists and it is denied by default. |
| `POST /api/users/fcm-token` | Called by push-notification registration; no backend mapping exists and it is denied by default. |
| `GET /api/cars/search` | Called by the car controller; the backend exposes car locations and nearby search, but not this route. |
| `GET /api/transfers/search` | Called by the transfer controller; the backend exposes transfer bookings and availability, but not this route. |

The client call paths above are confirmed in source. The actual user-visible error depends on whether a particular action is invoked; those flows were not all exercised in a signed-in preview session.

## External API inventory

All provider credentials are referenced as backend configuration/secrets. Their values were not opened, copied into this report, or tested directly.

| Provider/system | Use and integration | Key behavior / limitations |
|---|---|---|
| Supabase PostgreSQL | Persistent users, listings, bookings/trips, offers, preferences, landmarks, tokens, and related records; accessed by Spring JDBC/JPA | Configure with `SUPABASE_DB_URL`, `SUPABASE_DB_USER`, and `SUPABASE_DB_PASSWORD`; no Flutter direct database calls found. |
| Duffel | Flight offer search through `POST https://api.duffel.com/air/offer_requests`; Bearer token and `Duffel-Version: v2` | Search only. A 30-second in-process cooldown handles provider rate limits. No Duffel order-create call exists. |
| LiteAPI | Hotel rates through `POST /hotels/rates` at `https://api.liteapi.travel/v3.0`, using `X-API-Key` | Hotel information/prices only. Booking remains the local simulated partner flow; no LiteAPI prebook/book/cancel integration exists. |
| OpenTripMap | Tourist places, place details, and destination/geoname data at `https://api.opentripmap.com/0.1` | Backend caches search results for 24 hours, details for 7 days, and suggestions for 15 minutes. The code uses English results for Arabic searches because the provider does not document Arabic output. |
| Geoapify | Airport/location lookup and geocoding at `https://api.geoapify.com` | API key is sent as a query parameter. In-memory lookup caches last 30 minutes; configured connect/read timeouts are 3/5 seconds. |
| Requesty | AI chat at `https://router.requesty.ai/v1/chat/completions` | Backend bearer key; default model is `google/gemma-4-31b-it`; configured read timeout is 120 seconds. |
| Frankfurter | USD exchange-rate lookup at `https://api.frankfurter.dev/v2/rates?base=USD` | No key. Success results cache for 6 hours; failures are cached for 5 minutes to avoid repeated provider calls. |
| SerpAPI | Google Maps search through `https://serpapi.com/search.json` | `SERPAPI_KEY` is added by the server as a query parameter. Avoid logging full request URLs because query strings contain the key. |
| Google Places | Optional backend rating/place synchronization at `https://places.googleapis.com/v1` | Uses `GOOGLE_PLACES_API_KEY`. Startup logs reported the key was not configured, so this optional sync was skipped in the observed run. |
| Anthropic | Optional duplicate-landmark verifier at `https://api.anthropic.com/v1/messages` | Configured through `ANTHROPIC_API_KEY`; failures leave candidates for review. The README states no Anthropic credential is currently available. |
| OurAirports | Airport CSV import/synchronization at `https://ourairports.com/data` | Import script selects complete scheduled-service airport records and imports them additively into PostgreSQL. It is a data import, not a live per-search API. |
| OpenStreetMap tiles | Map imagery requested by the Flutter map client | Uses public tile URLs; verify required attribution and tile usage policy for production scale. |
| Firebase Cloud Messaging | Push notification client packages and token registration | Flutter attempts to register the token at the missing `/api/users/fcm-token` route, so server-side token persistence is not connected. |

No active Hotelbeds, RapidAPI, or Amadeus service implementation was found in backend or app source. Xotelo appears only in localized display text. No direct provider credentials are present in Flutter API code.

### Search and booking boundaries

- Flight search merges Duffel offers and partner inventory into the same client model. Duffel is not a booking provider in the current implementation.
- Hotel results merge LiteAPI rates and partner listings. LiteAPI is explicitly read-only; it does not book or pay for a room.
- `/api/payments/checkout` returns a `mock://checkout` URL and a `mock_...` session ID. The current implementation is a simulator, not a card processor.
- Zentrip can persist local trip/booking records for supported partner flows. That is not the same as issuing a real airline/hotel order to the external provider.
- Do not represent the current checkout as collecting or settling real payments.

## Database and data integrity

The schema contains **26 distinct application tables**:

`partners`, `users`, `password_reset_codes`, `partner_listings`, `airports`, `user_reviews`, `user_profiles`, `ai_chat_messages`, `travel_preferences`, `tourist_monuments`, `landmark_places`, `landmark_place_aliases`, `landmark_search_areas`, `landmark_merge_candidates`, `legacy_attraction_partner_reviews`, `attraction_visit_counts`, `attraction_visit_dedup`, `offers`, `offer_catalog_metadata`, `trips`, `flight_seat_holds`, `bookings`, `transfers`, `transfer_schedules`, `api_tokens`, and `hotel_destinations`.

Important relationships include users-to-partners, listings-to-partners, bookings/trips/transfers-to-users, bookings-to-partner-listings, seat holds-to-listings/users/trips, and transfer schedules-to-transfers. The current schema declares a foreign key for booking `user_id` and `partner_listing_id`, but partner/trip association fields do not have the same declared referential protection. Review those relationships before relying on them for deletes or reconciliation.

The recent booking-history implementation returns customer-scoped booking/trip data and normalizes price, image, end date, and room count without introducing new persistence tables. History endpoints return all rows rather than paging; growth will increase response size and database work.

### RLS finding

`20261101_role_access_rls.sql` defines policies for users, bookings, trips, transfers, listings, tokens, preferences, and related tables. However, neither `schema.sql` nor that role migration enables row-level security for those core tables. In PostgreSQL, policies are inert unless RLS is enabled on the table. The landmark and hotel-destination migrations do explicitly enable RLS on their own new tables, but that does not enable it on bookings, trips, users, or listings.

`RlsContextFilter` correctly opens a transaction, sets a non-login runtime role, and applies transaction-local user/role/partner settings. This is useful only if the target tables have RLS enabled and the migration is applied. The test harness currently does not apply the role migration, so passing local tests does not prove the core policies are active.

## Security and privacy review

### Strengths

- Backend role is loaded from `users` after validating a hashed bearer token; the client cannot choose its own role.
- Admin and partner controller prefixes are separately restricted by Spring Security.
- The API defaults to denying unmatched `/api/**` paths.
- Partner listing operations derive the partner identity from the verified request context and apply ownership filtering in backend queries.
- External API keys are read from backend properties/environment variables, not Flutter request code.
- Flight checkout passenger/passport fields are handled in the client booking flow; the reviewed persistence contract does not add passport/card fields to the existing trip/booking records.
- There is no real card gateway wired into the mock checkout.

### Risks and gaps

1. Core RLS policies are not enabled by the checked-in schema/migration, as described above.
2. The default CORS setting is `*` through `app.cors.allowed-origins`. Production should specify exact deployed web origins.
3. The Flutter bearer token is persisted with `SharedPreferences`, not a platform secure-storage plugin. Consider secure storage for production mobile builds and define backup behavior.
4. SerpAPI, Geoapify, and OpenTripMap use query-string API keys. Keep full URLs out of logs, exceptions, analytics, and request tracing. Duffel, LiteAPI, Requesty, Google Places, and Anthropic use headers.
5. The code enables OpenTripMap's free-plan mode while `app.commercial-use` defaults to true. Startup warns that the free plan is non-commercial. Confirm licensing or switch to an appropriate plan before commercial operation.
6. `app.cors.allowed-origins` has a permissive default; upload URLs are also exposed as static resources. Confirm upload access/content-type policy before accepting arbitrary public uploads.
7. Password reset delivery depends on mail configuration (`MAIL_ENABLED` defaults false). Production recovery must be tested with actual SMTP configuration; the API returning success alone does not prove the user received a code.

## Code quality, performance, localization, and tests

- Dynamic result screens generally use lazy list/grid builders; the source search found builder use across 14 files. Small fixed forms and cards use scroll views where eager construction is reasonable.
- Search debounce is present for flight, hotel destination/filter, attractions, map viewport, and home search flows. Car/transfers flows should be checked when their API contract is repaired.
- `CachedNetworkImage` is used in one file; the shared `AppNetworkImage` and profile photo use `Image.network`. Network images across hotel, attraction, and profile areas therefore do not consistently use the declared cache package.
- Shimmer is used in one file; several async feature loading states still use ordinary progress/loading placeholders. No `Hero` usages were found.
- English and Arabic localization assets exist. The backend/provider limitations mean some OpenTripMap place text may remain English during Arabic search. Arabic visual verification was not completed in this audit.
- `flutter pub outdated` completed. It reports newer versions for a number of dependencies; this is maintenance information, not evidence of a vulnerability. The dependency vulnerability audit reported zero findings.
- Flutter test suite: **167 tests passed**; `flutter analyze`: **no issues**.
- `bash scripts/test-backend.sh`: **212 passing**, with PostgreSQL-dependent tests skipped by design.
- `bash scripts/test-postgres.sh`: **213 tests passed, zero failures/errors, zero skipped** against a disposable local PostgreSQL instance.
- Important limitation: that PostgreSQL harness applies `schema.sql` and the landmark catalog migration, but not the role/RLS, airport, or hotel-destination migrations. It therefore does not test the full production migration set or prove core RLS enforcement.
- The configured Start Zentrip workflow starts and the backend connects to PostgreSQL in the development environment. A screenshot browser was unauthenticated and showed the public onboarding flow; the signed-in admin, partner, booking, and hotel-detail screens were not visually verified.
- Maven `dependency:analyze` could not inspect compiled output: its analyzer rejected Java 25 class-file version 69. This is a tooling compatibility limitation, not a demonstrated application compile failure. The project-wide dependency vulnerability scanner reported zero vulnerabilities.
- SAST reported two medium generic-PostgreSQL-string findings in `scripts/test_run_replit.py`. They are in a test helper and point to an example host; the embedded user-info is intentionally omitted here. Confirm those fixture values are not valid credentials. HoundDog reported zero findings.

## Prioritized findings (top 10)

| Priority | Finding | User/business impact | Recommended next action |
|---|---|---|---|
| P0 — High | RLS policies for core tables are created but RLS is not enabled in the checked-in base schema or role migration; the PostgreSQL test harness skips that migration. | The intended database-level isolation is not guaranteed; the app currently relies mainly on API query scoping. | Enable RLS for the intended tables, validate grants/policies against the runtime role, and add a test that applies the full role migration and proves customer/partner/admin isolation. |
| P1 — High | Six client API contracts have no matching backend route: social login, destination weather, visa info, FCM token registration, car search, and transfer search. | These actions fail when invoked (default-deny or missing route) even though corresponding client methods/screens exist. | Decide whether to implement or remove each flow; add contract tests for all client-called paths. |
| P1 — High | `/api/attractions/nearby` is mapped but absent from Spring Security matchers. | Nearby attraction calls are denied for valid customers. | Add the intended customer/public matcher and test anonymous/customer access explicitly. |
| P1 — High | Payments return a mock checkout session, and no Duffel/LiteAPI order-creation endpoint exists. | A user could mistake a simulated confirmation/local booking for a real provider booking or payment. | Keep the simulator clearly labeled until a provider order and payment lifecycle, idempotency, reconciliation, cancellation, and refunds exist. |
| P1 — High | OpenTripMap free-plan mode is enabled alongside commercial-use configuration. | Potential provider-terms/licensing noncompliance if the app is used commercially. | Confirm licensing with the provider and configure a compatible plan or disable the source for commercial traffic. |
| P2 — Medium | Default CORS allows `*`. | Any web origin can make browser requests; bearer auth still limits protected data, but broad origin policy increases exposure. | Set production `CORS_ALLOWED_ORIGINS` to exact trusted domains and verify preflight behavior. |
| P2 — Medium | SerpAPI/Geoapify/OpenTripMap credentials are embedded in query parameters. | Proxy/access logs can retain keys if full URLs are logged. | Ensure URL redaction in server, proxy, tracing, and error logs; rotate any key found in logs. |
| P2 — Medium | Flutter stores bearer tokens in `SharedPreferences`. | Tokens are not protected with a platform secure-storage mechanism. | Move auth tokens to secure storage, preserving logout/refresh semantics and testing backup behavior. |
| P2 — Medium | Hotel/place/profile image caching is inconsistent; shared image helper uses `Image.network`. | Repeat downloads and slower scrolling can increase data use and image decode churn. | Reuse cached-network image handling and define bounded cache/error/placeholder behavior. |
| P2 — Medium | Booking/history APIs return unpaged collections; integration tests do not apply every migration. | Response cost can grow with account history; regressions in migration/RLS behavior can pass current tests. | Add stable pagination and broaden the disposable PostgreSQL suite to apply/verify the full migration chain. |

## Stakeholder presentation points

- Zentrip is a Flutter client with a Spring Boot API and a Supabase-hosted PostgreSQL database; keys stay on the backend.
- The app currently combines partner inventory with Duffel flight offers and LiteAPI hotel prices, but checkout is simulated and does not place an external provider order.
- The backend derives roles from stored user records, restricts admin/partner APIs, and applies customer ownership filters.
- The most important security follow-up is enabling and testing PostgreSQL RLS on the core tables; policies alone do not enforce access.
- Several visible client features have no matching backend endpoint, so API contract coverage should be fixed before describing those features as operational.
- Current Flutter and backend tests pass, but the database test harness does not yet exercise the full production migration/RLS chain.

## Manual verification still required

1. Apply/inspect the complete migration chain on a disposable database first, then verify RLS is enabled on every intended table and test customer, partner, and admin isolation.
2. Confirm the production Supabase database has the expected migrations and runtime role/grants; this audit did not inspect production rows or change production data.
3. Validate the live Duffel, LiteAPI, OpenTripMap, Geoapify, Requesty, and SerpAPI credentials with safe provider requests. Secret values were not accessed.
4. Verify outbound email/password-reset delivery, Google/Apple sign-in, and FCM registration; the server-side endpoints/configuration are incomplete or environment-dependent.
5. Test the affected routes in a signed-in browser/device session, including admin, partner, flight checkout, hotel detail, Arabic RTL, nearby attractions, cars, and transfers.
6. Do not accept real payment or promise a confirmed external airline/hotel reservation until provider booking and payment integrations are implemented and reconciled.

## Audit execution and file count

**Files directly opened with targeted line reads:** 18 project files, plus the attached audit brief and the relevant uploaded-file/security instructions. Additional controllers, service files, migrations, tests, and UI files were searched with `rg`; those search-only files are not included in the 18-file direct-read count.

The 18 directly opened project files were:

1. `lib/core/services/api_service.dart`
2. `lib/routes/app_routes.dart`
3. `test/app_role_route_guard_test.dart`
4. `backend/src/main/java/com/zentrip/api/SecurityConfig.java`
5. `backend/src/main/java/com/zentrip/api/TokenAuthFilter.java`
6. `backend/src/main/java/com/zentrip/api/RlsContextFilter.java`
7. `backend/src/main/java/com/zentrip/api/WebConfig.java`
8. `backend/src/main/java/com/zentrip/api/ApiController.java`
9. `backend/src/main/java/com/zentrip/api/DuffelFlightService.java`
10. `backend/src/main/java/com/zentrip/api/LiteApiHotelService.java`
11. `backend/src/main/resources/application.properties`
12. `backend/src/main/resources/migrations/20261101_role_access_rls.sql`
13. `scripts/test-postgres.sh`
14. `scripts/start-replit.sh`
15. `pubspec.yaml`
16. `backend/pom.xml`
17. `README.md`
18. `backend/README.md`

Commands/checks run during this audit included route and call-site searches (`rg`), schema/migration inspection, `flutter analyze`, `flutter test`, `bash scripts/test-backend.sh`, `bash scripts/test-postgres.sh`, `flutter pub outdated --no-dev-dependencies`, Maven `dependency:analyze`, and the platform dependency/SAST/HoundDog scans.

Only `docs/APP_ANALYSIS.md` was added for this audit; application source files were not changed.
