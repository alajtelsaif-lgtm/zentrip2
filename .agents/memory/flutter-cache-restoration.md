---
name: Flutter cache restoration
description: Restored workspace toolchains do not guarantee the global Pub cache is still available.
---

Do not assume a retained Flutter SDK, web build, or package configuration means that the global Pub package cache is intact.

**Why:** The SDK and generated configuration can persist inside the workspace while referenced packages under the home-directory Pub cache disappear between sessions. Even formatting can then fail on a missing lint include.

**How to apply:** Restore the existing locked dependencies with the workspace Flutter SDK's `pub get` before formatting or testing when cached package paths are missing. Do not upgrade dependencies or remove lint configuration to work around a missing cache.
