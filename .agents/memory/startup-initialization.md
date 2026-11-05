---
name: Nonblocking startup initialization
description: Keep optional preferences and plugin initialization from blocking the first rendered screen.
---

Render the application before initializing optional services, isolate initialization failures with bounded waits, and never let onboarding-preference persistence block navigation.

**Why:** Waiting for all preference/plugin setup before rendering left the browser preview white. A slow or failed optional service must not hide the startup screen, and a browser storage failure must not trap users in onboarding.

**How to apply:** Do not add new optional services to a blocking pre-render initialization chain. They should initialize independently while the existing startup/session flow runs. Bound onboarding preference reads/writes and continue routing when storage is unavailable.
