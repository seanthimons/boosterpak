# Safely deinitialize a boosterpak project

Removes selected project-local boosterpak and renv artifacts while
preserving unrelated project files and user-level configuration. An
interactive call with all component arguments omitted offers the
actionable components, preselects all of them, and then confirms the
exact cleanup plan. Supplying any component argument skips the picker
but still confirms the plan. Non-interactive cleanup requires
`force = TRUE`; genuine no-op calls do not prompt or require `force`.

## Usage

``` r
deinit(
  root = ".",
  renv = TRUE,
  boosters = TRUE,
  rprofile = TRUE,
  lockfile = TRUE,
  air = TRUE,
  force = FALSE,
  verbose = NULL
)
```

## Arguments

- root:

  Existing project root.

- renv:

  Whether to remove the project-local `renv/` directory.

- boosters:

  Whether to remove `boosters.toml` and `boosters/`.

- rprofile:

  Whether to remove boosterpak-managed `.Rprofile` content.

- lockfile:

  Whether to remove `renv.lock`.

- air:

  Whether to remove an unchanged boosterpak-generated `air.toml`.

- force:

  Whether to skip interactive selection and confirmation.

- verbose:

  Whether to print routine summaries.

## Value

An invisible list with normalized `root`, actionable `selected`
components, successfully `removed` relative paths, `rprofile_changed`,
named `preserved` reasons, `restart_required`, and `cancelled`.

## Details

`air.toml` is removed only when its complete line sequence matches a
known boosterpak-generated format. `.Rprofile` is never deleted: only
recognized managed startup, repository, and install-policy content is
removed, along with a whole-line renv activation expression when both
`renv` and `rprofile` are `TRUE`. Malformed startup markers and all
unrelated profile lines are preserved.

## See also

[`init()`](https://seanthimons.github.io/boosterpak/reference/init.md)
