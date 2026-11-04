---
name: Supabase RLS runtime
description: Constraints for applying row-level security to backend requests over Supabase's transaction pooler.
---

The application database connection uses Supabase's transaction pooler and the `postgres` role can bypass RLS. Backend queries must run inside a transaction after switching to a dedicated non-login, non-bypass role and setting transaction-local user/role/partner context from verified authentication.

Zentrip authenticates with its own `users` and `api_tokens` tables, not Supabase Auth. Do not assume `auth.uid()` or a `users.auth_user_id` column exists. `TokenAuthFilter` validates the token before the RLS transaction begins; that narrow lookup still runs under the configured JDBC login. Controller queries then run with the non-bypass runtime role and server-derived transaction-local context.

Never infer the live Supabase RLS state from checked-in migrations alone. A baselined/manual database can diverge: during verification, the live visit-count tables had RLS disabled and `anon`/`authenticated` table privileges despite the current migration chain enabling RLS.

**Why:** Existing owner policies do not constrain a backend connection with `BYPASSRLS`, and session-level role state is unsafe with transaction pooling. The managed `postgres` role also cannot necessarily have role attributes altered by the application migration user. Live migration history may not record manual SQL application.

**How to apply:** Create and grant a separate runtime role with safe attributes; do not weaken the managed `postgres` role. Apply `SET LOCAL ROLE` and trusted identity settings within each request transaction, derive identity only from the verified API token/user row, then validate policies against the real PostgreSQL engine. Before and after production migrations, inspect live RLS flags, policy definitions, and `anon`/`authenticated` table grants; verify the configured JDBC login's RLS-bypass attributes separately because token lookup precedes the role switch.
