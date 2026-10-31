---
name: Imported database safety
description: Why Replit startup must not silently reconcile account roles in an imported database.
---

Environment setup must preserve existing database schema and account access unless changes are explicitly approved.

**Why:** The imported application's bootstrap demotes partner users and deactivates partners not listed in its environment configuration. An absent partner list during setup does not mean the user wants existing partners removed.

**How to apply:** Keep automatic role reconciliation disabled for imported databases. Before enabling startup maintenance, explain the effects and confirm that the complete partner configuration is supplied. Do not initialize, replace, or reset the existing external database to make setup easier.
