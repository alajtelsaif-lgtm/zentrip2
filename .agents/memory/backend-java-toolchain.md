---
name: Backend Java toolchain
description: Use the workspace JDK for Java backend builds and tests.
---

Run backend Maven commands with `.local/toolchains/jdk` as `JAVA_HOME` and prepend its `bin` directory to `PATH`. The system Java runtime is older than the backend compiler target.

**Why:** The backend targets Java 25, while the default system Java in this workspace is Java 21. The Maven wrapper is also absent, so invoking system Maven with the default JDK fails before tests compile.

**How to apply:** For backend compile or test commands, explicitly select the workspace JDK before invoking `mvn`.
