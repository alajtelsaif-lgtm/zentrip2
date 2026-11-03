---
name: UI design reference rules
description: Use user-provided screenshots as the source of truth for Zentrip screens.
---

Match each provided screen screenshot closely, without redesigning it. Reuse existing theme values, shared widgets, and components where they fit. Implement screens in the order the user sends them; before a screen's reference arrives, build only its logic and a simple placeholder UI. Treat screenshot text as sample data, bind real booking state, localize every label in English and Arabic, and keep layouts correct in Arabic RTL.

**Why:** the user asked that supplied screenshots be the source of truth for Zentrip UI.

**How to apply:** For every screen task, compare the implementation with its supplied screenshot; do not hardcode example values or introduce duplicate design components. State any details that were unclear or could not be matched in the completion report.
