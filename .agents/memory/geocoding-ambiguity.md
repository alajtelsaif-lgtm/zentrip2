---
name: Geocoding ambiguity
description: Geoapify free-text results can resolve to homonymous places in unexpected countries or regions.
---

Do not trust the first free-text geocoding result to respect an explicit country or identify the best-known destination. Normalize full country names to ISO codes before OpenTripMap geoname requests, and reject geoname results whose country differs from the requested code.

**Why:** Geoapify resolved a Bali query to Taiwan without a country filter, and to a small Indonesian village when the country was repeated in the text. OpenTripMap returned a Utah location for “Leptis Magna, Libya” when its country filter was omitted.

**How to apply:** Resolve explicit country hints to ISO codes and apply the provider's country filter; verify the returned country as well. For Geoapify, avoid repeating the country in filtered text. Use returned coordinates for nearby-POI queries instead of geocoding an ambiguous city name again. Require disambiguation for unknown country hints.
