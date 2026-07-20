# Synchronize a boosterpak project

Synchronize a boosterpak project

## Usage

``` r
sync(
  mode = c("apply", "restore"),
  root = ".",
  hydrate = TRUE,
  verbose = NULL,
  library = NULL
)
```

## Arguments

- mode:

  `"apply"` installs packages declared by `boosters.toml` and writes
  `boosters/attach.R`; `"restore"` restores from `renv.lock`.

- root:

  Project root.

- hydrate:

  Whether additive apply mode should reuse packages from
  renv-discoverable local libraries before downloading with pak. Restore
  mode and active-library apply mode ignore this option.

- verbose:

  Whether to print routine summaries.

- library:

  Package-library strategy for apply mode: `"renv"` uses the
  project-local renv library, while `"active"` uses the first writable
  entry in [`.libPaths()`](https://rdrr.io/r/base/libPaths.html). `NULL`
  uses `[settings].library`, defaulting to `"renv"`.

## Value

Resolved package names, invisibly.
