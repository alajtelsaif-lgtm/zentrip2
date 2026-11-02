---
name: Wikidata availability
description: Runtime behavior and fallback when public Wikidata SPARQL is unavailable.
---

Keep Geoapify as the spatial source and request Wikidata SPARQL in parallel. If SPARQL times out, batch Geoapify Wikidata IDs through the public `wbgetentities` API to recover labels, descriptions, images, and sitelinks. Continue returning a partial-results warning; entity enrichment is not equivalent to a successful spatial query.

**Why:** The application runtime repeatedly timed out on `query.wikidata.org`, while the Wikidata entity API responded successfully.

**How to apply:** Preserve Geoapify results during SPARQL failures, use bounded entity batches, and report the partial provider state honestly.
