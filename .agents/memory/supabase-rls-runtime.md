---
name: Supabase RLS runtime
description: Constraints for applying row-level security to backend requests over Supabase's transaction pooler.
---

The application database connection uses Supabase's transaction pooler and the `postgres` role can bypass RLS. Backend queries must run inside a transaction after switching to a dedicated non-login, non-bypass role and setting transaction-local user/role/partner context from verified authentication.

**Why:** Existing owner policies do not constrain a backend connection with `BYPASSRLS`, and session-level role state is unsafe with transaction pooling. The managed `postgres` role also cannot necessarily have role attributes altered by the application migration user.

**How to apply:** Create and grant a separate runtime role with safe attributes; do not weaken the managed `postgres` role. Apply `SET LOCAL ROLE` and trusted identity settings within each request transaction, then validate the policies against the real PostgreSQL engine before relying on them.
