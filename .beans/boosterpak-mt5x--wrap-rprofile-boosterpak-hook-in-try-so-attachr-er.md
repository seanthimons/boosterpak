---
# boosterpak-mt5x
title: Wrap .Rprofile boosterpak hook in try() so attach.R errors don't abort the profile
status: todo
type: bug
priority: critical
tags:
    - blocker
created_at: 2026-07-09T18:23:44Z
updated_at: 2026-07-09T18:23:44Z
---

## Problem

The .Rprofile hook written by init() (string in R/constants.R:49-51) is a single unguarded expression:

    if (dir.exists("boosters")) { attach <- file.path("boosters", "attach.R"); if (file.exists(attach)) source(attach); invisible(lapply(list.files("boosters", "^fn_.*\.R$", full.names = TRUE), source)) }

On a fresh clone (packages not yet restored), `source(attach)` errors on the first missing `library()` call. Verified consequences (R 4.5.1):

- The `fn_*.R` lapply in the same `{}` never runs.
- The error aborts the REST of .Rprofile: any user lines after the hook (options(repos=...), Sys.setenv, credentials) silently never run in that session. Interactive R continues with a degraded profile; Rscript prints "Execution halted" and the script body does not run at all.
- If the user then runs renv::restore() relying on repos/options set later in .Rprofile, restore uses the wrong configuration.

The hook is inserted immediately after `source("renv/activate.R")` by insert_after_renv_activation (R/rprofile.R:41-48), so anything the user keeps after that point is exposed.

## Fix

Wrap the hook body (at minimum the `source(attach)` call, preferably the whole expression) in `try()` in R/constants.R so a missing package warns instead of aborting the profile. Update the hook string that init() writes; note existing projects keep the old hook — consider whether sync()/status() should detect and offer to upgrade it.

## Origin

Surfaced during review of PR #3 (restoring-a-project vignette). The vignette's "these errors are harmless" claim was scoped as a caveat (fix A); this bean is the root-cause fix (fix B). Blocks all development work per owner's direction.
