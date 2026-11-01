---
name: Duffel stay inventory boundary
description: Read-only Duffel hotel search and authoritative display pricing.
---

In unified hotel inventory, Duffel stays are read-only: display fetched offers, but do not quote, book, or mutate existing booking records from this path. Use fetched rates as the authoritative display price; the initial search estimate is not a confirmed offer.

**Why:** The user explicitly scoped this inventory integration to data retrieval and display, and Duffel's initial hotel search response can contain only an estimate.

**How to apply:** Fetch and normalize the available rates before showing a price. If rates fail, retain the hotel result without a price and show a warning rather than presenting the preliminary estimate as final.
