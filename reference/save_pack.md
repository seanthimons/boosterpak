# Save a resolved package set as a pack

Save a resolved package set as a pack

## Usage

``` r
save_pack(
  name,
  scope = c("project", "user"),
  from = NULL,
  root = ".",
  functions = "installed",
  overwrite = FALSE,
  verbose = NULL
)
```

## Arguments

- name:

  Pack name to write.

- scope:

  Destination scope: `"project"` or `"user"`.

- from:

  Optional existing pack name to fork. When `NULL`, captures the current
  project's resolved package set.

- root:

  Project root.

- functions:

  Functions to carry with the pack: `"installed"`, `"all"`, `"none"`, or
  a character vector of function names.

- overwrite:

  Whether to replace an existing pack file.

- verbose:

  Whether to print routine summaries.

## Value

Path to the saved pack, invisibly.
