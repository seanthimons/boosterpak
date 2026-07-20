# Remove a pack declaration

Remove a pack declaration

## Usage

``` r
remove_pack(
  name,
  root = ".",
  sync = TRUE,
  remove_functions = FALSE,
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

- remove_functions:

  Whether to remove unchanged function files provided only by the
  removed pack.

- verbose:

  Whether to print routine summaries.

- library:

  Package-library strategy passed to
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md).
  `NULL` uses the project configuration.

## Value

Updated declared pack names, invisibly.
