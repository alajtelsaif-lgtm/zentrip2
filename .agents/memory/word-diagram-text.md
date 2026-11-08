---
name: Word diagram text
description: Editing text embedded in editable shapes in older Word documents.
---

Editable diagram labels in Word may be duplicated across DrawingML and legacy VML fallback representations. Updating only the DrawingML text can leave the visible label unchanged in Word.

**Why:** This document retained its diagram text in both representations, so the first edit affected neither visible fallback label.

**How to apply:** Inspect the shape XML and update matching text in both `a:t` DrawingML nodes and `w:t` text-box fallback nodes while preserving the existing shape geometry and run styling.
