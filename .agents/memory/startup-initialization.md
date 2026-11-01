---
name: Nonblocking startup initialization
description: Keep optional preferences and plugin initialization from blocking the first rendered screen.
---

Render the application before initializing optional services, and isolate initialization failures with bounded waits.

**Why:** Waiting for all preference/plugin setup before rendering left the browser preview white. A slow or failed optional service must not hide the startup screen.

**How to apply:** Do not add new optional services to a blocking pre-render initialization chain. They should initialize independently while the existing startup/session flow runs.
