# Zentrip Java

This is a copy of the Zentrip Flutter app with the same assets and visual UI, paired with a Java Spring Boot backend in `backend/`.

## Java toolchain

Use JDK 25 or newer to run the backend and Android Gradle build. The Android app continues to compile Java and Kotlin to Java 17 bytecode; its Gradle wrapper is pinned to 9.1.0 for Java 25 runtime support.

## Run the backend

Configure `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, and `SERPAPI_KEY` as described in [backend/README.md](backend/README.md), then run `mvn spring-boot:run` from `backend/`.

## Backend tests

Run the mock-based backend suite with `bash scripts/test-backend.sh`. The PostgreSQL migration and HTTP integration tests are intentionally skipped by that command because it unsets database settings and does not start a database.

To run the full suite, including those PostgreSQL tests, use `bash scripts/test-postgres.sh`. It creates a fresh temporary PostgreSQL cluster bound only to `127.0.0.1`, loads `backend/src/main/resources/schema.sql`, runs all backend tests, then stops and removes the cluster. It does not connect to Supabase or use application database credentials. PostgreSQL server tools (`initdb`, `pg_ctl`, `createdb`, and `psql`), Maven, and JDK 25 are required.

The full PostgreSQL suite also runs in GitHub Actions on pushes and pull requests via `.github/workflows/backend-postgres.yml`.

## Run Flutter

From this project root, run:

```powershell
flutter pub get
flutter run -d chrome --dart-define=ZENTRIP_API_URL=http://127.0.0.1:8080/api
```

The copied app targets the Java API in `backend/`. Android emulators use `http://10.0.2.2:8080/api`; desktop and web builds use `http://127.0.0.1:8080/api`. VS Code's Run and Debug menu includes Chrome and Windows configurations pinned to the local API URL. For a physical phone, run Flutter with `--dart-define=ZENTRIP_API_URL=http://<computer-LAN-IP>:8080/api` and allow port 8080 through the computer's firewall.# zentrip

## Admin dashboard

The Flutter app includes a responsive, Arabic/English admin dashboard with live customer, reservation, and booked-value summaries. Admin endpoints verify the account role on every request; customer accounts remain the default.

To grant the first admin role, create the intended account, then start the backend with `APP_ADMIN_EMAIL` set to that existing account's exact email. The backend promotes only that account at startup. Alternatively, a database administrator can promote an existing account directly with `UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';`. Never expose admin promotion through a public endpoint.# zentrip

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Worldwide landmark catalog

Landmark discovery uses OpenTripMap as the only tourism POI provider. Keep
`OPENTRIPMAP_API_KEY` in Replit Secrets; the backend reads it and the Flutter app
never receives it. OpenTripMap does not document Arabic responses, so Arabic
searches use supported English place text. When a city query is Arabic, Geoapify
is used only as a country-aware geocoder before OpenTripMap fetches the POIs; it
is not a tourism data source. If OpenTripMap cannot resolve another city and a
country is supplied, the same geocoding fallback is used. Keep provider
attribution and follow OpenTripMap/OSM licensing terms.

The catalog migration is additive and leaves the existing `tourist_monuments`
table unchanged. Back up the target database, ensure
`20261101_role_access_rls.sql` has run, then apply
`backend/src/main/resources/migrations/20261102_landmark_catalog.sql` in Supabase.
Without the migration, live OpenTripMap search still works, but persistent
30-day caching and global alias search are unavailable.

Exact provider/Wikidata identities and places under 50 m apart are canonicalized.
Places 50–300 m apart remain separate and are queued for review unless the
duplicate verifier is configured. The importer never deletes places or rewrites
legacy tables. The current environment has no Anthropic credential, so ambiguous
places stay in the review queue. To enable automated checks, add `ANTHROPIC_API_KEY`
to backend Secrets and, if needed, set `ANTHROPIC_MODEL`. Verifier failures remain
in the review queue. Never put either value in Flutter or a client `.env` file.

The duplicate audit is read-only and requires a verified backup file:

```sh
bash scripts/audit-landmark-duplicates.sh --dry-run --backup /path/to/backup.dump
```

It reports up to 500 nearby or shared-Wikidata candidates from the new catalog.
It has no apply mode. Legacy curated monuments have no coordinates in their
current schema and are excluded.

Map searches request only visible bounds, debounce map movement in Flutter, and
return clusters at low zoom. Search responses and aliases are cached in the
database for 30 days; the app does not download the entire world.
