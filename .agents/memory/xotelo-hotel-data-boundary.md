---
name: Xotelo hotel data boundary
description: What Xotelo's public hotel API can provide and where access is restricted.
---

Xotelo's direct API supports hotel lists, OTA rate comparisons, and rate heatmaps when given known TripAdvisor location or hotel keys. The hotel's search endpoint is RapidAPI-only; an unauthenticated direct request returns 401. The API provides comparison data, not reservation or booking confirmation.

**Why:** A successful rate/list response does not mean the service provides open-ended city search, confirmed availability, or bookable inventory.

**How to apply:** Use Xotelo as a read-only discovery or price-comparison supplement when the required TripAdvisor keys and access are available. Confirm access limits and commercial-use terms before production, and keep booking on a real booking provider.
