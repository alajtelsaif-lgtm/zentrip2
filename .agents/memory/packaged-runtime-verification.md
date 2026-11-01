---
name: Packaged runtime verification
description: Source tests do not establish that the running packaged application includes current changes.
---

Verify the served API contract after rebuilding the packaged application, not only the source tests.

**Why:** The launcher previously reused an existing JAR and web bundle while source tests compiled newer classes. Successful tests and restarts therefore left the preview running older code.

**How to apply:** When test results disagree with live responses, check artifact freshness before changing business logic. A Maven test run does not itself update an executable JAR.
