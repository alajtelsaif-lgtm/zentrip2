---
name: Replit preview framing
description: Diagnoses blank Replit previews when the application loads directly.
---

When a page works by direct URL but the Replit preview is blank, inspect the response framing headers before assuming the Flutter renderer failed. Spring Security's default `X-Frame-Options: DENY` blocks Replit's embedded preview.

**Why:** The browser preview loads the app in a separate iframe; a healthy server and successful direct screenshot can coexist with a blank preview when framing is denied.

**How to apply:** Keep production framing denied. For the Replit development workflow, disable `X-Frame-Options` only when needed and pair it with a restricted CSP `frame-ancestors` allowlist for Replit origins.
