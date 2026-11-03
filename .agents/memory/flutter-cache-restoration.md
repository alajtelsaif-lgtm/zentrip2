---
name: Flutter cache restoration
description: Restored workspace toolchains do not guarantee the global Pub cache is still available.
---

Use the workspace Flutter SDK for project commands; the Nix-provided Flutter on PATH can be older than the dependency constraints. Do not assume a retained SDK, web build, or package configuration means the global Pub cache is intact.

**Why:** The workspace toolchain may satisfy the project while the system Flutter cannot resolve its locked packages, and referenced Pub packages may also disappear between sessions. Changing dependencies to accommodate the older system SDK would break the project’s intended toolchain.

**How to apply:** Prefer `.local/toolchains/flutter/bin/flutter`; run `pub get` there before formatting or testing when cached package paths are missing. Do not downgrade dependencies or remove lint configuration to work around a missing or stale system SDK/cache.
