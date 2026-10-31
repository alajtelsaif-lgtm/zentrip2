---
name: Anonymous visit abuse limits
description: Privacy constraints and deployment tradeoffs for throttling public attraction visits.
---

Protect public attraction popularity counts with aggregate, short-lived request limits rather than per-IP or per-account quotas. Do not persist visitor identities or location data to enforce the limit.

**Why:** Anonymous visit counting must remain usable without collecting account or location data, while distinct fabricated visitor tokens can otherwise distort rankings.

**How to apply:** If the API scales beyond one process, coordinate aggregate counters across instances without introducing visitor, account, or IP identifiers. Remember that process-local limits reset on restart and are not shared by replicas.
