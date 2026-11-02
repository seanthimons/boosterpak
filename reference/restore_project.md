# Restore a project without capability packs

Restores the exact versions in `renv.lock`. Before restoration,
normalizes Posit Package Manager Linux URLs in the lockfile and removes
Linux Platform tags. Package versions and non-PPM repositories are
preserved. No `boosters.toml`, packs, or attachment hooks are required
or created. Public P3M repositories use Cloud CRAN as a binary fallback.
Explicit private overrides, repository dates, and repository opt-outs
are preserved.

## Usage

``` r
restore_project(root = ".", require_binaries = character())
```

## Arguments

- root:

  Project root containing `renv.lock`.

- require_binaries:

  Package names that must resolve to binaries. Restore stops before
  installation if a named package would use source.

## Value

The restored package records, invisibly.
