---
name: PostgreSQL migration verification
description: Why migration checks need real PostgreSQL instead of only mocked JDBC expectations.
---

Database compatibility changes require tests against a disposable real PostgreSQL database, not only mocked JdbcTemplate calls.

**Why:** During the MySQL migration, mocks accepted invalid multi-assignment JSON updates and wrong parameter counts. Several tests still matched MySQL SQL fragments, so passing tests did not demonstrate that the PostgreSQL path executed correctly. PostgreSQL's default generated-key results also differ from MySQL's.

**How to apply:** Exercise actual controller requests, generated IDs, inventory changes, rollback, and repeated cancellation using isolated PostgreSQL fixtures. Keep external database credentials out of test environments, restrict integration test URLs to loopback, and use live connections only for read-only metadata and health checks unless writes are explicitly approved.

PostgreSQL CSV COPY treats unquoted empty fields as null. Optional source strings must be nullable in staging and explicitly normalized before insertion into non-null target columns.

**Why:** Blank optional airport keywords caused an otherwise valid bulk import to fail with a not-null violation.

**How to apply:** Validate COPY staging behavior with genuinely empty optional values, not only fully populated fixtures; preserve required-field checks for identifiers and coordinates.
