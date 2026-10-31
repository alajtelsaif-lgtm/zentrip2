# Zentrip on Replit

This repository keeps its existing Flutter frontend and Java Spring Boot backend.

## Run

Use the **Run** button (`Start Zentrip` workflow), or:

```sh
bash scripts/start-replit.sh
```

Spring Boot serves both the compiled Flutter web app and `/api` on `0.0.0.0:5000`.
Web API requests use the same origin; mobile/desktop API configuration is unchanged.

## Build after editing

```sh
bash scripts/build-replit.sh
```

Then restart the workflow. The web preview serves a release build, not hot reload.
The build script installs local SDKs if missing, resolves Flutter dependencies,
builds the web app, runs isolated backend unit tests, and packages the Java backend.
The full PostgreSQL integration suite runs separately using the command below.

SDKs are Flutter 3.44.0 and Java 25, stored in ignored `.local/toolchains/`.
Maven and Python are configured in `.replit`. Do not commit SDKs or build outputs.

## Database and safety

The existing Supabase database is retained. Configure secrets through Replit Secrets:

- `SUPABASE_DB_URL`: PostgreSQL URI (optionally containing credentials) or JDBC URL.
- `SUPABASE_DB_PASSWORD`: required if the URL does not contain a password.
- `SUPABASE_DB_USER`: optional; otherwise uses the URL username, then `postgres`.

The launcher normalizes connection settings without logging credentials.
Pooler connections must use the pooler's exact username, not always `postgres`.
Port 6543 connections disable server-side prepared statements to avoid
Supabase transaction-pooler session collisions. The backend also defaults
PG JDBC `prepareThreshold` to zero, including when started outside this launcher.

For this imported database, the Replit launcher defaults to:

- `DB_SCHEMA_INIT=never`: do not initialize or reset the schema.
- `APP_BOOTSTRAP_ENABLED=false`: do not run startup schema maintenance or role reconciliation.

The existing bootstrap resets partner access unless all partner accounts are
configured. Enable it only deliberately after reviewing the database and
`APP_PARTNER_ACCOUNTS`. Running the backend outside the Replit launcher retains
its original bootstrap behavior.

## External features

Core app startup does not require optional provider keys. AI chat requires
`REQUESTY_API_KEY`; map search uses `SERPAPI_KEY`; Google Places synchronization
uses `GOOGLE_PLACES_API_KEY`. Email recovery requires the SMTP and password-reset
settings documented in `backend/README.md`. Missing configuration must be reported
explicitly, not replaced with invented credentials or simulated success.

Payments in the imported project are mock payments, not real charges.
Profile photos use `backend/uploads`; durable production storage needs a separate review.

## Checks

```sh
python3 scripts/test_run_replit.py
.local/toolchains/flutter/bin/flutter test
bash scripts/test-backend.sh
bash scripts/test-postgres.sh
```

`test-postgres.sh` creates a temporary loopback-only PostgreSQL database, applies
the schema there, exercises real HTTP-controller/JDBC flows, and removes the
temporary database when finished. It explicitly removes the external database
secrets from its environment. Never point integration tests at Supabase.

Provider secrets configured in Supabase Vault or Edge Functions are not
automatically injected into this Java process. Configure the keys above in this
Replit project's Secrets for the corresponding features to work.

For local preview only, `ZENTRIP_PROVIDER_ENV_FILE` can select an ignored uploaded
environment file. The launcher reads only `REQUESTY_API_KEY`, `REQUESTY_MODEL`,
`SERPAPI_KEY`, and `GOOGLE_PLACES_API_KEY`; existing environment variables take
precedence. It does not apply database, admin, partner, or service-role values
from that file. Uploaded `.env` files are excluded from Git and publishing.
Use Replit Secrets rather than this local-file option for publishing.

The launcher disables automatic Google Places startup synchronization to prevent
unrequested API usage and database updates when a provider key is first added.
Explicit hotel listing updates can still request rating synchronization.
