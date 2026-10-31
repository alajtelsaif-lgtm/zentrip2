---
name: Seat inventory fidelity
description: Why flight seat presentation must distinguish actual inventory from reference-image examples.
---

Do not invent cabin partitions or class-specific seat availability to match a visual reference.

**Why:** The supplied seat-selection reference has multiple cabin buttons and different class counts, while the imported flight inventory uses a shared seat pool without physical fare-class allocations. Fabricating separate counts could imply seats can be sold that the backend cannot fulfill.

**How to apply:** Preserve shared-inventory labeling and use actual configured cabin ranges. Separate per-class availability requires corresponding backend allocation and booking enforcement, not just different numbers in the interface.
