# Synchronize a boosterpak project

Synchronize a boosterpak project

## Usage

``` r
sync(mode = c("apply", "restore"), root = ".", hydrate = TRUE, verbose = NULL)
```

## Arguments

- mode:

  `"apply"` installs packages declared by `boosters.toml`; `"restore"`
  restores from `renv.lock`.

- root:

  Project root.

- hydrate:

  Whether additive apply mode should reuse packages from
  renv-discoverable local libraries before downloading with pak. Restore
  mode ignores this option and remains lockfile-exact.

- verbose:

  Whether to print routine summaries.

## Value

Resolved package names, invisibly.
