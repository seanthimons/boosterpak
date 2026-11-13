---
# boosterpak-83qe
title: Review failing tests
status: completed
type: task
priority: normal
created_at: 2026-05-29T16:18:43Z
updated_at: 2026-11-13T22:30:00Z
---

## Resolution

No failing tests remain. The full testthat suite passes locally on v0.12.0 (only the opt-in live tests and Windows-only tests skip), and R CMD check passes on ubuntu, windows and macos in CI.
