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
  verbose = NULL
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

  Whether additive sync should reuse packages from renv-discoverable
  local libraries before downloading with pak.

- overwrite_functions:

  Whether to overwrite existing function files provided by the pack.

- verbose:

  Whether to print routine summaries.

## Value

Updated declared pack names, invisibly.
