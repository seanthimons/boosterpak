# Initialize a boosterpak project

Creates or repairs the project files, then records the installed
boosterpak version in `[project].boosters_version` of `boosters.toml`.
That field is the version the project was last migrated with. It is
written only once the `.Rprofile` startup step has run, so a new project
created with `rprofile = "no"`, or where the prompt is declined, has no
record and still counts as behind until a later `init()` completes that
step. The record is never moved to an older version.
[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
does not change it.

## Usage

``` r
init(
  root = ".",
  renv = c("ask", "yes", "no"),
  rprofile = c("ask", "yes", "no"),
  verbose = NULL
)
```

## Arguments

- root:

  Project root.

- renv:

  Whether to initialize project-local renv: `"ask"`, `"yes"`, or `"no"`.

- rprofile:

  Whether to add the recommended `.Rprofile` startup hook that sources
  `boosters/attach.R` before helper files.

- verbose:

  Whether to print routine summaries.

## Value

Project setup paths, invisibly.
