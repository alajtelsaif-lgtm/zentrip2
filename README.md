# Zentrip Java backend

Spring Boot replacement API for the copied Flutter application. The API keeps the existing `/api` paths and JSON contract for authentication, trips, bookings, transfers, mock payments, and SerpAPI map search.

## Requirements

- Java 25 or newer
- Maven 3.9+
- Supabase PostgreSQL database with the project connection string, username, and password configured below

## Configure

Create a local environment file once by copying the example, then edit `backend/.env` with your Supabase credentials:

```powershell
Copy-Item .env.example .env
```

Keep values unquoted (`KEY=value`). `.env` is ignored by Git; do not commit it or paste its secrets into chat.

Use a Supabase Postgres URL in the form below, or pass the same values via your deployment platform environment variables:

```dotenv
SUPABASE_DB_URL=jdbc:postgresql://db.<YOUR_SUPABASE_PROJECT_REF>.supabase.co:5432/postgres?sslmode=require
SUPABASE_DB_USER=postgres
SUPABASE_DB_PASSWORD=your-supabase-db-password
DB_URL=${SUPABASE_DB_URL}
DB_USERNAME=${SUPABASE_DB_USER}
DB_PASSWORD=${SUPABASE_DB_PASSWORD}
```

If you use Supabase's transaction pooler, switch to the pooler hostname and port `6543` instead of the direct database port `5432`:

```dotenv
SUPABASE_DB_URL=jdbc:postgresql://aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=require&channelBinding=require
```

The schema initializer creates missing tables; it does not delete or reset an existing database. The project is currently configured for PostgreSQL/Supabase compatibility, and any legacy MySQL-specific SQL should be reviewed against PostgreSQL equivalents before running against Supabase.

## Password recovery

Password reset codes are six digits, expire after 10 minutes, and are limited to five verification attempts. To enable email recovery, configure `MAIL_ENABLED=true`, SMTP host/port/username/password, `MAIL_FROM`, and a unique `PASSWORD_RESET_HMAC_SECRET` of at least 32 characters in `backend/.env`, then restart the backend. Until SMTP is configured, the recovery API returns an explicit unavailable response rather than claiming that a message was sent. The reset-code table is created automatically by the schema initializer.

## Admin dashboard

The Flutter app provides a responsive Arabic/English admin dashboard backed by authenticated `/api/admin/dashboard`, `/api/admin/reservations`, and `/api/admin/customers` endpoints. Every endpoint checks the caller's database role; new users receive the `customer` role by default.

To configure the initial administrator, first create the account, then set `APP_ADMIN_EMAIL` in the backend environment to that existing account's exact email and restart Spring Boot. The backend promotes only that matching account. You can also use a trusted database administrator to promote an existing account with `UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';`. Do not add public role-promotion endpoints. The booked-value metric is the sum of non-cancelled reservation prices; it is not a payment-provider settlement or audited revenue report.

## Supplier partner portal

The Flutter app also includes an Arabic/English partner extranet inspired by the supplier workflows used by travel marketplaces. It is not connected to Booking.com. A partner must first register as a normal Zentrip user; then add that account's exact email to `APP_PARTNER_ACCOUNTS` in `backend/.env` and restart the backend:

```dotenv
APP_PARTNER_ACCOUNTS=libyanairlines@zentrip.ly|libyan-airlines|Libyan Airlines|airline;afriqiyahairlines@zentrip.ly|afriqiyah-airlines|Afriqiyah Airways|airline;buraqairlines@zentrip.ly|buraq-air|Buraq Air|airline;libyanwings@zentrip.ly|libyan-wings|Libyan Wings|airline;almasahotel@zentrip.ly|al-masa-hotel|Al-Masa Hotel|hotel;zentripcarrental@zentrip.com|zentrip-car-rental|Zentrip Car Rental|car
```

Each entry uses `email|company-slug|company-name|service-type`, and multiple entries are separated by semicolons. Supported service types are `airline`, `hotel`, `car`, `attraction`, `transfer`, and `travel` (travel packages). Use only addresses that have registered and are authorized by the company. The exact configured accounts are the allow-list: removing an entry revokes that account's partner role and disables that company's listings on the next backend startup. Partner requests are checked against the active database role, and reservations, listings, and guest details are scoped to the assigned company.

To add the Al-Masa Hotel and Zentrip Car Rental demo partners, first register accounts with `almasahotel@zentrip.ly` and `zentripcarrental@zentrip.com`. Add their entries from the configuration example above to the existing `APP_PARTNER_ACCOUNTS` value (preserving other authorized entries), then restart the backend. The startup bootstrap creates/activates each partner record and assigns the existing users' `role` and `partner_id`; it intentionally does not create accounts or passwords. Verify both accounts show `role = 'partner'` and the expected `partners.service_type`, then run `backend/scripts/seed_partner_demo_inventory.sql` against the Zentrip database. The script is safe to rerun: it adds one hotel listing with Standard, Deluxe, and Family Suite rates and three rental vehicles (economy sedan, SUV, and luxury sedan) only when their stable seed keys are absent. Restart the backend after seeding so the startup Google Places sync can populate the hotel's Google rating when the API key is configured.

The seed includes an available-room count for the hotel and example vehicle counts and an availability schedule for the next 365 days as descriptive mock metadata. Hotel bookings reserve the requested room count atomically from `available_rooms`; cancellations restore the reserved rooms. This is global inventory, not date-specific capacity, and it is not automatically replenished after a completed stay. Rental booking endpoints do not enforce date-specific capacity.

Hotel listings use the shared `partner_listings` table with explicit hotel columns for `location_name`, `google_maps_url`, `place_id`, `google_rating`, `google_review_count`, `amenities`, `tax_and_fees_percentage`, and `available_rooms`; the listing title and price columns are exposed as `name` and `price_per_night`. New databases receive the fields from `schema.sql`; on startup, the backend adds any missing hotel columns to existing databases and backfills location, amenities, tax values, and room inventory from legacy JSON attributes. `backend/scripts/migrate_hotel_listing_fields.sql` remains available for a manual migration before startup; do not run it after startup has already added the columns. Neither migration converts Zentrip customer-review aggregates into Google ratings.

Hotel partners can enter a Google Maps URL, coordinates, or Place ID. Google rating and review count are read-only and fetched by the backend Places API service after a listing is created or its Maps/Place ID changes. The service also retries active listings with zero/unverified Google values when the backend starts. Configure `GOOGLE_PLACES_API_KEY` in `backend/.env`, enable the Google Places API (New), and restrict the key to server-side use; the key is never sent to Flutter. Hotel rows use `0.0` and `0` as explicit “not yet verified” database/API defaults; only successful Places responses replace them with official values. Sync attempts, outcomes, and failures are logged without exposing the API key. Coordinate pairs and coordinates embedded in full Google Maps URLs are parsed and stored as numeric latitude/longitude values. Nearby search logs and excludes active listings without valid coordinates.

The user-facing hotel model uses a string listing ID and the fields `name`, `location_name`, `google_maps_url`, `place_id`, `google_rating`, `google_review_count`, `amenities`, `description`, `price_per_night`, `tax_and_fees_percentage`, and `available_rooms`. The partner form edits these fields except Google-sourced rating/review values. Amenities are stored as individual strings. The nightly price defaults to a 12% taxes/fees rate. Flutter and Java compute subtotal, taxes/fees, and total from the number of nights and requested rooms; booking checkout uses the computed total. Hotel photos are selected from the device and uploaded with authenticated `POST /api/partner/hotel-images` multipart requests (`image` field, JPEG/PNG/WebP, at most 5 MB each). The first photo is the cover image and remaining photos are stored as the listing gallery; files are served from `/uploads/` under `UPLOAD_DIR`. Customer hotel search uses active partner inventory, database-backed destination suggestions for cities, districts, addresses, and landmarks, and GPS nearby search within a default 50 km radius. Hotels without enough available rooms are shown as sold out and cannot be booked. If device location is denied, unavailable, simulated as `0,0`, or returns no nearby results, the Flutter app searches the Tripoli demo area and tells the user. Nearby results are sorted by Haversine distance.

Partners can add/edit structured listings only for their configured specialty: airlines manage flights, hotel partners manage hotels, car providers manage rentals, and other service accounts manage their corresponding service. The API enforces this restriction as well as the dashboard. The dashboard uses typed fields for standard attributes and validated JSON arrays for hotel room-rate tiers and availability schedules; the saved nested attributes, cover/gallery URLs, status, prices, and location values round-trip through the partner listing API. The dashboard derives country and location metadata from the selected supported city or airport. Listing reference codes and flight numbers are generated by the server from the company identity and database listing ID and cannot be supplied or changed by a partner. Flight routes use the `airports` table, seeded by `schema.sql`, which stores city, country, airport name, region, and airport code; city locations for the other current services come from the same registry. Hotel listings require an uploaded cover photo. The rate is per seat for flights, per night for hotels, per day for cars, per person for attractions, per ride for transfers, and the total per person for a package; booking creation recalculates the saved amount from the current listing rate and booking dates instead of trusting a client-supplied amount. Service-specific searchable fields (for example flight route codes and departure date) are saved in listing attributes; newly created listings are published by default unless explicitly paused, and public inventory includes only active listings owned by active partners. `GET /api/airports/search?query=...` searches the airport directory. `GET /api/flights/search` filters active partner flight listings by route, departure date, passenger capacity, and seat class; it returns database inventory only and does not substitute mock flights when the backend fails. The optional return date is accepted and validated, but flight listings currently represent individual outbound legs. Inventory's live/paused switch is a simple global availability control, not date-specific room, vehicle, or seat capacity management. Checkout and payments remain mock flows; connect contracted supplier systems, authoritative date-specific capacity, and a payment provider before using this as a commercial booking platform.

Flight bookings are checked against the travel dates of existing trips, regardless of airline. Taxi bookings are rejected when their pickup-to-drop-off time window overlaps another active taxi booking for the same account.

Flight partners choose either `airbus_a320` (3-3 layout, 30 rows, 180 seats) or `atr72` (2-2 layout, 16 rows, 64 seats). The API normalizes and validates the aircraft name, layout, row count, capacity, and available seats; unsupported or mismatched inventory is rejected. Authenticated `GET /api/flights/{flightId}/seats` returns occupied seats and layout metadata. `POST /api/flights/{flightId}/seats/reserve` holds the requested seats for 15 minutes; `DELETE` on that route releases the current account's unconfirmed hold. After checkout, authenticated `POST /api/bookings/confirm` accepts `flight_id`, `seats`, `seat_class`, optional `return_date`, and optional `extras` (`extra_baggage` at $18 or `flexible_ticket` at $12), then creates the trip and returns its booking reference, confirmed seats, extras, and server-calculated total. Holds and confirmed seats are stored in `flight_seat_holds`; expired holds are ignored and cleaned up during new reservations. Checkout remains mocked, as described below.

`GET /api/bookings` returns the account's hotels, car rentals, attraction tickets, and travel packages for My Trips. `DELETE /api/bookings/{id}` marks an owned non-completed booking as cancelled; completed bookings and bookings owned by another account cannot be cancelled.

The Home destination ideas and offers load from `GET /api/offers`. The backend seeds six demo offers into the `offers` table with `INSERT IGNORE`; edit those rows to customize the demo catalog. Replace seeded offers with contracted supplier inventory before commercial launch.

## Run

```powershell
cd backend
mvn spring-boot:run
```

The API runs at `http://127.0.0.1:8080/api`. Start the copied Flutter app from the `zentrip_java` root using `flutter run`.

Zen AI uses the authenticated `POST /api/ai/chat` endpoint. The Java backend streams Requesty's OpenAI-compatible chat-completions response to the app as server-sent events, so text appears as soon as the provider generates it. The app sends up to 10 recent messages per user and chat session and allows up to 512 generated tokens. Replies follow the latest user message's language, with the app language as a fallback. Set `REQUESTY_API_KEY` and `REQUESTY_MODEL` in `backend/.env`; a lower-latency model available to your Requesty account may improve the time to the first token and total response time. Restart the backend after changing these settings. Never place the key in Flutter code or commit it to Git.

For example, if this model is available in your Requesty account:

```dotenv
AI_PROVIDER=requesty
REQUESTY_API_KEY=your_requesty_key
REQUESTY_MODEL=google/gemma-4-31b-it
```

Requesty chat completions are sent to `https://router.requesty.ai/v1/chat/completions`. Confirm the exact model identifier in the Requesty model library. Restart Spring Boot after changing these settings.

Users can edit their personalization profile under **Profile → Travel Preferences**. The authenticated `GET` and `PUT /api/preferences/travel` endpoints store budget level, travel pace, trip length, party size, interests, and preferred destination per account. Zen loads that profile for each chat response; users can still override it in their latest message.

Flight trips are checked for schedule overlap per customer using UTC departure and arrival times. Legacy trips without an arrival time conservatively occupy 24 hours. Cancellation preserves the trip and records a refund request as `pending_airline_review`, targeting the original payment method if the fare is refundable. This is a demo workflow only: airline fare rules determine eligibility, and no real refund is issued until a payment provider and airline/refund integration are configured.

While Zen is generating, the chat input becomes a Stop button; quick prompts and repeat sends are disabled. Stop cancels the app's stream and prevents a late reply from being saved. Closing the stream may not stop provider-side work or usage immediately.

Authenticated profile updates use `POST /api/profile` with multipart `name`, `phone`, and an optional `photo` (JPEG, PNG, or WebP; maximum 5 MB). The photo is served from `/uploads/` and stored in `UPLOAD_DIR` (defaults to `backend/uploads`). `PUT /api/profile/password` accepts `current_password`, `password`, and `password_confirmation` as JSON. Keep the upload directory writable and persistent; use private object storage and HTTPS for production deployments.

The payment endpoints intentionally retain the existing mock checkout behavior; connect a real payment provider before production use. Saved places remain local to the Flutter app, as in the original project.