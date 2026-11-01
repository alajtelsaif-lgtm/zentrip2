---
name: Imported database safety
description: Why Replit startup must not silently reconcile account roles in an imported database.
---

Environment setup must preserve existing database schema and account access unless changes are explicitly approved.

**Why:** The imported application's bootstrap can demote partner users and deactivate partners not listed in its environment configuration. An absent or partial startup list does not mean existing partners should be removed, and must not undo administrator-managed account changes.

**How to apply:** Keep automatic role reconciliation disabled for imported databases. Before enabling startup maintenance, explain the effects and confirm that the complete partner configuration is supplied. Do not initialize, replace, or reset the existing external database to make setup easier.

Provider integrations must adapt incoming flight and hotel data to the existing models and booking persistence, rather than replacing tables, queries, ORM, local storage, or state management.

**Why:** The user explicitly required preserving the approved legacy storage mechanism during provider integration.

**How to apply:** Keep provider search metadata separate from persisted partner bookings. Do not send external offers through the partner booking path unless a compatible reservation flow has been implemented.
