---
name: Wikidata SPARQL URI encoding
description: Avoid Spring URI-template expansion failures for brace-delimited SPARQL queries.
---

Percent-encode a complete SPARQL query before constructing its request URI for Spring `RestClient`. The URI builder treats `{ ... }` in a SPARQL query parameter as URI-template syntax and may throw a missing-variable exception before the request is sent.

**Why:** A live Wikidata enrichment request failed with a URI-template expansion error because the query contains braces, preventing otherwise valid Geoapify place results from being returned.

**How to apply:** For Wikidata or other brace-heavy query languages sent through Spring `RestClient`, encode query text with UTF-8 and pass a concrete URI rather than the raw query through the URI-builder template expansion path.
