# Remove a pack declaration

Removes the pack from `boosters.toml`, drops its
`[settings.packs.<name>]` section when no remaining pack needs it, and
regenerates `boosters/attach.R` so its packages stop attaching at
startup. This happens whether or not `sync` is `TRUE`.

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

  Whether to print routine summaries and the note about packages that
  remain installed. `FALSE` suppresses both.

- library:

  Package-library strategy passed to
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md).
  `NULL` uses the project configuration.

## Value

Updated declared pack names, invisibly.

## Details

Removing a pack does not uninstall anything. Packages it provided stay
in `renv.lock` and the project library; run
[`renv::snapshot()`](https://rstudio.github.io/renv/reference/snapshot.html)
to drop them from the lockfile and
[`renv::remove()`](https://rstudio.github.io/renv/reference/remove.html)
to uninstall them. A note saying so is printed unless `verbose = FALSE`.
