---
name: Backend test database isolation
description: Safe PostgreSQL test setup and avoiding real connection settings in Maven logs.
---

Never let Maven tests inherit the configured external database URL or password. For real PostgreSQL integration checks, create a disposable local database and use the integration test's loopback-only URL guard.

**Why:** Spring can include a malformed datasource URL in startup exceptions, exposing connection settings in diagnostic output. Mock-based test runs also should not connect to the imported application database.

**How to apply:** Prefer `scripts/test-backend.sh` for mock-based tests. For PostgreSQL integration tests, provide only loopback test connection settings and tear down the disposable database after the run.
