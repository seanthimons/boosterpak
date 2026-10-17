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
declared and resolved packs, package and missing-package counts, attach
state, materialized function drift/missing counts, pack catalog counts,
selected package-library strategy and path, renv state, lockfile
presence, and `.Rprofile` hook state.

The attach fields are `attach_enabled`; `attach_packages`, the names of
every attached package, and `attach_package_count`, its length; and
`attach_every_start_count`, the number of those packages attached on
every R start, including workers. `attach_interactive_packages` names
the packages attached only in interactive sessions
(`attach_mode = "interactive"` packs). `attach_sources` is a data frame
with one row per attached package and columns `package`, `pack`, and
`interactive`. `pack` names the packs that requested the package, or
`"[attach].declared"` for packages listed in `boosters.toml`.
`interactive` is `TRUE` for interactive-only packages.

`upgrade_needed` is `TRUE` when `boosters.toml` exists and its
`boosters_version` record is missing, unreadable, or older than the
installed boosterpak. Only an older or unreadable record, or an earlier
`.Rprofile` layout, prints a warning. A missing record is reported as
"no version recorded" and prints no warning, because a project created
with `init(rprofile = "no")` has none. A `.Rprofile` with no boosterpak
hook is informational, not a warning. Run
`upgrade_project(dry_run = TRUE)` before
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
when a warning asks for it.

`github_token_visible` is `NA` unless the project declares GitHub
sources (`owner/repo` specifications from `[extras].declared` or from
pack `sources`). Then it is `TRUE` when a token is visible through the
`GITHUB_PAT` or `GITHUB_TOKEN` environment variables or, when the
gitcreds package is installed, through its credential store. The token
value is never returned or printed.
