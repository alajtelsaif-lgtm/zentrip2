---
name: Flight checkout data boundary
description: Keep passenger and payment data within the existing booking storage contract.
---

Flight checkout may collect passenger identity and passport fields in transient UI state, but must not add database fields or persist those values through a new mechanism. The app has no saved-card model; never show a fabricated card number or claim that a payment method is stored.

**Why:** The requested booking-flow work preserves the approved legacy storage and simulated-payment behavior.

**How to apply:** Prefill only profile values already available (name, email, phone), pass checkout values through the current flow, and save only through the existing trip/booking path unless the user explicitly approves a storage change.
