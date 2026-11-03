---
name: Hotelbeds hotel-data boundary
description: Provider scope and booking behavior for Zentrip hotel inventory.
---

Use Hotelbeds only for hotel availability and content data. Do not call Hotelbeds rate-check or reservation endpoints, and never pass provider rate keys into the app. Hotel checkout continues through Zentrip's existing simulated payment and booking-record flow.

**Why:** The user explicitly wants hotel data from Hotelbeds while keeping booking simulated like partner bookings.

**How to apply:** Normalize provider availability and content into the existing hotel model, preserve partner inventory as a fallback, and keep booking persistence and payment on the existing Zentrip path.
