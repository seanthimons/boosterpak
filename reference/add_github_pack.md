# Import booster packs from a GitHub repository

`add_github_pack()` clones a repository, discovers booster pack
manifests under `path`, copies selected packs into the current project's
`boosters/packs/` directory, declares them in `boosters.toml`, and
optionally runs the normal additive sync flow.

## Usage

``` r
add_github_pack(
  repo,
  packs = NULL,
  ref = NULL,
  path = ".",
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite = FALSE,
  overwrite_functions = FALSE,
  verbose = NULL
)
```

## Arguments

- repo:

  GitHub repository as `"owner/repo"` or a git URL.

- packs:

  Character vector of pack names to import, `"all"` to import all
  discovered packs, or `NULL` to select interactively.

- ref:

  Optional git ref to check out after cloning.

- path:

  Directory inside the repository that contains pack manifests.

- root:

  Project root.

- sync:

  Whether to run additive sync after editing TOML.

- hydrate:

  Whether additive sync should reuse packages from renv-discoverable
  local libraries before downloading with pak.

- overwrite:

  Whether to replace existing project pack files.

- overwrite_functions:

  Whether to overwrite existing function files provided by the pack.

- verbose:

  Whether to print routine summaries.

## Value

Updated declared pack names, invisibly.
