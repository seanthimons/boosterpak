# Report boosterpak project status

Report boosterpak project status

## Usage

``` r
status(root = ".", verbose = NULL)
```

## Arguments

- root:

  Project root.

- verbose:

  Whether to print routine summaries.

## Value

A list describing project status, invisibly. Includes config validity,
declared and resolved packs, package and missing-package counts,
materialized function drift/missing counts, pack catalog counts, renv
state, lockfile presence, and `.Rprofile` hook state.
