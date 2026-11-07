---
name: RLS catalog reads
description: Row-locking reads of public catalog records may interact with admin-only update policies.
---

Do not use `SELECT ... FOR SHARE` or `FOR UPDATE` for a customer-facing catalog lookup unless the runtime role's row-level security policies intentionally permit that lock. Use a plain read for public offer metadata; keep locks for state that the customer is authorized to mutate or reserve.

**Why:** A package offer was visible through the public offers endpoint but disappeared from a confirmation lookup that used `FOR SHARE`, because the offers table permits updates only to admins under runtime RLS.

**How to apply:** When adding locking reads to offers, partner listings, or other public catalog tables, test the query under the real runtime role and current-user RLS context, not only as the database owner.
