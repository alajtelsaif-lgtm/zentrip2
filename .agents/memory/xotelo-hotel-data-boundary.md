---
name: Xotelo hotel data boundary
description: What Xotelo's public hotel API can provide and where access is restricted.
---

Xotelo's direct API supports hotel lists, OTA rate comparisons, and rate heatmaps when given known TripAdvisor location or hotel keys. The hotel's search endpoint is RapidAPI-only; an unauthenticated direct request returns 401. A successful location-list request returns hotel names, images, review summaries, coordinates, and price ranges, but its minimum price is only an estimate and availability is unconfirmed.

**Why:** A successful rate/list response does not mean the service provides open-ended city search, confirmed availability, or bookable inventory. Zentrip's booking flow is separate and remains a simulated local payment/booking record.

**How to apply:** Use Xotelo only as a read-only hotel-data source when verified TripAdvisor location keys are available; direct city search needs RapidAPI access. Keep Xotelo records unlinked to partner inventory and preserve Zentrip's booking flow. Confirm access limits and commercial-use terms before production.
