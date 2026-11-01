---
name: Geocoding ambiguity
description: Geoapify free-text results can resolve to homonymous places in unexpected countries or regions.
---

Do not trust the first free-text geocoding result to respect an explicit country or identify the best-known destination.

**Why:** Geoapify resolved a Bali query to Taiwan without a country filter, and to a small Indonesian village when the country was repeated in the text. A country-filtered query for just the place name resolved the intended island.

**How to apply:** Resolve explicit country hints to ISO codes and apply the provider's country filter. Avoid repeating the country in the filtered text. Use the returned coordinates for nearby-POI queries instead of geocoding a potentially ambiguous city name again. Require disambiguation for unknown country hints.
