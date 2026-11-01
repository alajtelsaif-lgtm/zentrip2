---
name: Packaged runtime verification
description: Source tests do not establish that the running packaged application includes current changes.
---

Verify the served API contract after rebuilding the packaged application, not only the source tests.

**Why:** The launcher previously reused an existing JAR and web bundle while source tests compiled newer classes. Successful tests and restarts therefore left the preview running older code.

**How to apply:** When test results disagree with live responses, check artifact freshness before changing business logic. A Maven test run does not itself update an executable JAR.

Do not leave the server running against an executable JAR that has been replaced by a build or merge.

**Why:** Spring Boot lazily loads classes from the archive. Replacing it under a running process caused missing-class errors even though the replacement archive contained the classes; API routes could still work while static-page requests hung.

**How to apply:** After a merge rebuilds the JAR, restart the workflow before validating the app. Compare the running process start time with the archive modification time when only some routes fail.
