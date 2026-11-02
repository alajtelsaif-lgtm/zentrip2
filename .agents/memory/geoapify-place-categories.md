---
name: Geoapify Places categories
description: Use the provider's exact category taxonomy for landmark requests.
---

Geoapify Places category filters must use exact documented category names. In this project, the valid beach category is `beach`, and garden areas use `leisure.park.garden`; guessed paths such as `natural.beach` or `leisure.garden` should not be sent.

**Why:** A live Tripoli request successfully geocoded the city but returned zero place candidates with guessed category paths. Replacing them with the documented taxonomy returned candidates, of which verified Wikidata records could then be selected.

**How to apply:** Check the current Geoapify Places taxonomy before changing the categories list, and add a request-contract test for every non-obvious category.
