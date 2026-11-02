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
