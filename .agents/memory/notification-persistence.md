---
name: Notification persistence rollout safety
description: Keep successful bookings independent from the notification table rollout while preserving user-visible alerts.
---

Notification storage is additive: a missing notification migration must not make flight or other booking transactions fail. When the table is absent, skip the server insert, report the inbox API as temporarily unavailable, and preserve a local booking alert. Once server storage is available, a matching booking reference makes the persisted notification authoritative and removes the local duplicate.

**Why:** production database migrations are applied manually, so backend code can be released before the new inbox table exists. Booking is a core transaction and must continue to succeed during that rollout window.

**How to apply:** preserve the table-readiness guard and local fallback when changing notification writes or reads. Do not claim cross-device persistence is active until the notification migration is applied and verified.
