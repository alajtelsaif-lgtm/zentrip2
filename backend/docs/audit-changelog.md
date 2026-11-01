# Zentrip backend and search audit

## Project context

The attached brief describes a Python/Flask application that calls Supabase
through a Supabase SDK. This repository is a Flutter application with a Spring
Boot backend using JDBC against PostgreSQL. The fixes below follow the code and
database path that actually exist here; they do not introduce a new ORM,
Supabase client, or storage mechanism.

## Findings and changes

- **API access control:** Admin and partner routes are role-gated, customer
  routes require the customer role, login and account recovery remain public,
  and unlisted `/api/**` routes are denied. Public search routes are explicitly
  allow-listed. This closes the previous default-allow gap for API routes while
  leaving Flutter's static app paths accessible.
- **Flight search:** Partner and Duffel results use the existing response
  contract. Flexible Duffel date searches are concurrency-limited, stop
  scheduling additional dates after a rate-limit response, and return sanitized
  warnings alongside any results. Provider failures do not erase partner
  results.
- **Hotel search:** Partner inventory and Duffel Stays use the existing hotel
  response contract. Search results include per-source counts and safe
  warnings when either source is unavailable. The existing endpoint for
  fetching room rates remains in place.
- **Airport picker:** The flight picker now queries the backend airport
  directory rather than filtering only the built-in list. Input is debounced
  by 350 ms and stale in-flight responses are ignored.
- **Landmarks:** Shopping malls and unrelated commercial categories are
  excluded. Invalid Geoapify category names that caused HTTP 400 responses
  were removed. If a country has no saved attractions, the controller falls
  back to up to three scheduled-service cities in the airport directory. This
  fallback depends on the airport import and does not cover every city.
- **Currency display:** Traveler comparison controls are restricted to USD,
  EUR, and GBP. These conversions affect comparison/display only; persisted
  booking amounts and provider currencies are unchanged.
- **Taxi/car colors:** Car-rental controls and prices now use the same primary
  blue as the taxi/transfer screen. Semantic rating, success, and error colors
  remain unchanged.
- **Arabic strings:** English and Arabic localization keys remain aligned.
  This verifies key coverage, not a human linguistic review of every Arabic
  translation.

### Code files updated

- `SecurityConfig.java` — role-specific API rules and deny-by-default API
  handling.
- `DuffelFlightService.java`, `DuffelStayService.java`, and
  `PartnerController.java` — provider warnings, safer flexible-search
  concurrency, and partner/provider result aggregation.
- `flight_search_screen.dart` — backend-backed, debounced airport search.
- `car_rental_screen.dart` and `car_detail_screen.dart` — align car-rental
  accent color with the transfer screen.
- `GeoapifyAttractionService.java` — landmark-only category filtering and
  sanitized provider failure diagnostics, including rejection reasons without
  logging provider response bodies.
- `currency_service.dart`, `price_comparison.dart`, and `money_format.dart` —
  supported display currencies and formatting.
- `flight_results_screen.dart`, `flight_controller.dart`,
  `api_service.dart`, and English/Arabic localization files — partial-provider
  warning propagation and localized empty-state messaging.
- Backend and Flutter test files cover the changed access, provider,
  currency, and UI contracts.

## Access matrix

| Access | Routes |
| --- | --- |
| Public account access | `POST /api/auth/register`, `/api/auth/login`, `/api/auth/forgot-password`, `/api/auth/verify-code`, `/api/auth/reset-password` |
| Any authenticated role | `GET /api/auth/me`, `POST /api/auth/logout` |
| Admin | `/api/admin/**` |
| Partner | `/api/partner/**` |
| Customer | `/api/trips/**`, `/api/bookings/**`, `/api/transfers/**`, `/api/payments/**`, flight seat routes, attraction visit route, `/api/maps/**`, `/api/ai/**`, travel preferences, profile routes, and review creation |
| Public read/search | `GET /api/reviews`; airport, flight, hotel, car, inventory, offer, attraction-search, and exchange-rate routes explicitly allow-listed in `SecurityConfig` |
| Denied by default | Any other `/api/**` route; unauthenticated API requests receive 401, and authenticated requests without the required role are rejected |

## Environment variable names

The application configuration references the following names. No values are
included here:

`SUPABASE_DB_URL`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`, `DB_URL`,
`DB_USERNAME`, `DB_PASSWORD`, `DB_POOL_SIZE`, `DB_MIN_IDLE`,
`DB_CONNECTION_TIMEOUT`, `DB_IDLE_TIMEOUT`, `DB_MAX_LIFETIME`,
`DB_PREPARE_THRESHOLD`, `DB_SCHEMA_INIT`, `DUFFEL_ENABLED`,
`DUFFEL_ACCESS_TOKEN`, `GEOAPIFY_API_KEY`, `GOOGLE_PLACES_API_KEY`,
`REQUESTY_API_KEY`, `REQUESTY_MODEL`, `APP_ADMIN_EMAIL`,
`APP_PARTNER_ACCOUNTS`, `APP_PARTNER_RECONCILIATION_ENABLED`,
`CORS_ALLOWED_ORIGINS`, `SERVER_PORT`, `SMTP_HOST`, `SMTP_PORT`,
`SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_AUTH`, `SMTP_STARTTLS`,
`MAIL_ENABLED`, `MAIL_FROM`, `PASSWORD_RESET_HMAC_SECRET`, `SERPAPI_KEY`,
`UPLOAD_DIR`.

Keep all secret values in Replit Secrets or the deployment environment. Do not
commit an `.env` file.

## Verification performed

- `bash scripts/test-backend.sh`: 177 tests passed; 21 PostgreSQL integration
  tests were skipped because this run did not use a disposable PostgreSQL
  integration database.
- `flutter test`: all 128 tests passed.
- `flutter analyze`: no issues found.
- Rebuilt and restarted `Start Zentrip`: the workflow is running, Spring Boot
  reports the PostgreSQL pool started, `/` returns HTTP 200, airport lookup
  returns DXB for `query=DXB`, and an unauthenticated travel-preferences request
  returns HTTP 401.
- A live, read-only Geoapify search for Coimbra, Portugal returned 20
  attractions after the category-filter correction.
- No database schema migration or production data mutation was made.

## Remaining validation and scope limits

- The run logs previously showed Duffel flexible-search 429 responses. The
  concurrency cap and graceful warnings reduce repeated overload, but a valid
  provider account/quota and successful live search still need to be confirmed
  in the Replit environment.
- The backend connects directly to PostgreSQL with JDBC. Supabase PostgREST RLS
  policies are not in this request path, so policy behavior was not inferred
  from the app. A successful JDBC connection does not prove that every
  production table/query is healthy. Run the PostgreSQL integration suite only
  against a disposable test database.
- Country-level fallback searches at most three cities from the imported
  airport directory; it is not an exhaustive crawl of every city. Coverage
  depends on that import. Use a selected city for precise results and do not
  treat Geoapify as a complete, verified global landmark catalog.
- Creating a Duffel order is not part of the changes in this audit. It must be
  completed as a separate, explicit booking flow with passenger validation,
  payment state, idempotency, and provider test-mode verification. No live
  bookings were created.
- Taxi city-boundary enforcement and a complete content review of all Arabic
  translations were not validated by these changes.
- End-to-end parity for hotel amenities/rating/room filters across partner and
  Duffel inventory was not verified.

## Manual checks

1. Sign in with one test account per role. Confirm `/api/admin/**` is admin-only,
   `/api/partner/**` is partner-only, and customer data routes reject other
   roles.
2. Search airports by city, airport name, and IATA code. Confirm results come
   from the backend directory, and rapid typing does not issue a request per
   keystroke.
3. Search one city with both partner and Duffel enabled. Inspect `sources` and
   `warnings`; confirm a provider outage leaves the other source's results
   available.
4. Search hotels with dates and inspect partner/Duffel counts and warnings;
   open a Duffel result to fetch its available room rates.
5. Check English and Arabic screens and verify the comparison currency selector
   offers only USD, EUR, and GBP.
6. Run `bash scripts/test-postgres.sh` only after configuring its disposable,
   loopback PostgreSQL test database. Do not point it at production.
