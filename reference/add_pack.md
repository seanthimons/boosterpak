# Add a pack declaration

Add a pack declaration

## Usage

``` r
add_pack(
  name,
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite_functions = FALSE,
  verbose = NULL,
  library = NULL
)
```

## Arguments

- name:

  Pack name.

- root:

  Project root.

- sync:

  Whether to run additive sync after editing TOML.

- hydrate:

  Whether renv-library additive sync should reuse packages from
  renv-discoverable local libraries before downloading with pak. The
  active library strategy ignores this option.

- overwrite_functions:

  Whether to overwrite existing function files provided by the pack.

- verbose:

  Whether to print routine summaries.

- library:

  Package-library strategy passed to
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md).
  `NULL` uses the project configuration.

## Value

Updated declared pack names, invisibly.
