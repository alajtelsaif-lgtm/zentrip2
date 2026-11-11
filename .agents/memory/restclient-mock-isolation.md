---
name: RestClient mock isolation
description: Keep external provider unit tests network-isolated when services configure RestClient.
---

Provider-service tests must ensure their mock HTTP request factory remains active. If a service constructor replaces the injected `RestClient.Builder` request factory with a production factory, a test using `MockRestServiceServer` may unexpectedly call the real provider.

**Why:** A Requesty 403 test bypassed its mock server because the service replaced the builder's test request factory.

**How to apply:** Provide an injectable built client or an explicit test seam, and confirm provider tests pass without external credentials or network access.
