---
name: OpenTripMap landmark source
description: Provider boundary and language constraints for destination landmark discovery.
---

Landmark search, suggestions, and place records use OpenTripMap. A linked Wikipedia article may be queried only to obtain an image when OpenTripMap has no image; it is not a POI source. Keep Geoapify's independent airport and geocoding behavior unchanged. OpenTripMap documents English and Russian, so Arabic requests must use one consistent English card rather than mixing fields.

**Why:** The project explicitly chose OpenTripMap as its landmark provider and the official API does not offer Arabic responses. The requested Wikipedia image fallback is a narrow exception, not permission to add another POI provider.

**How to apply:** Do not restore Geoapify tourism-POI or Wikidata SPARQL calls. Keep the server-side OpenTripMap key private, retain strict provider-kind/business/location/identity/deduplication checks, and confirm OpenTripMap commercial terms before production use.
