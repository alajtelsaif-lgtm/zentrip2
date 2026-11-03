---
name: LiteAPI hotel-data boundary
description: LiteAPI supplies hotel search data and prices only; Zentrip retains simulated booking and payment.
---

Use LiteAPI for hotel availability, displayed rates, and hotel metadata. Keep the API key on the backend and preserve partner hotel listings as the fallback. Do not call LiteAPI prebook, booking, or cancellation endpoints; checkout remains Zentrip's existing simulated partner-payment flow.

**Why:** the user asked to use LiteAPI for hotel data while keeping booking simulation.

**How to apply:** when changing hotel search or detail screens, normalize provider results into the existing hotel contract without turning them into external bookings.
