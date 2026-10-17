# Upgrade an existing boosterpak project

`upgrade_project()` brings a project created by an earlier boosterpak
version up to date. It repairs the managed `.Rprofile` startup lines,
rewrites the managed `boosters/attach.R`, materializes missing built-in
packs, installs missing workflow packages (renv, pak, and boosterpak)
into the project library, and snapshots those packages into `renv.lock`.

## Usage

``` r
upgrade_project(root = ".", dry_run = FALSE, snapshot = TRUE, verbose = NULL)
```

## Arguments

- root:

  Project root containing an existing `boosters.toml` file.

- dry_run:

  Whether to report planned changes without modifying files, the project
  library, or the active session. Default `FALSE`.

- snapshot:

  Whether to write workflow packages to `renv.lock`. With `FALSE` the
  upgrade still repairs project files and installs missing workflow
  packages into the project library, but does not write the lockfile.

- verbose:

  Whether to print the upgrade report. `NULL` prints in interactive
  sessions. A dry run prints its report when `verbose` is `NULL`.

## Value

The upgrade report, invisibly. Its `actions`, `skipped`, `warnings`,
`paths`, and `preview` fields list what was done, or would be done, and
which files are affected.

## Details

Run a dry run first. `upgrade_project(dry_run = TRUE)` changes no files,
installs no packages, and restores the session options it touched. It
prints the planned actions, a preview of the `renv.lock` changes, and
the files a real run would touch.

The snapshot records the R version that runs the upgrade and the CRAN
repository URL in use, so run the upgrade from the R version the project
should pin. Package entries installed from Posit Package Manager
binaries can carry `Repository: RSPM` and a `Platform` field. renv's
restore code does not read `Platform`, and `RSPM` is only a preference:
restore falls back to the repository URLs listed in `renv.lock`, which
also serve Windows and macOS binaries. Use `snapshot = FALSE` to leave
`renv.lock` unchanged.

A clean real run records the installed boosterpak version in
`[project].boosters_version` in `boosters.toml`. A run is clean when its
report has no warnings. Steps that are skipped on purpose, such as
repository configuration disabled by an option or a project without a
project renv, do not make a run unclean. A missing renv does, because
the workflow packages cannot be repaired without it. A run that is not
clean repairs what it can, leaves the record as it was, and reports why.
A dry run changes nothing. It lists `boosters.toml` among the files a
real run would touch when that run would record the version.

Review the result with `git diff` (or your version control) before
committing. When an install fails with a GitHub rate limit, or with an
HTTP 403 or 429 from GitHub that may be a rate limit, the error includes
a hint about supplying a GitHub token. The hint never prints a token
value.

## Examples

``` r
if (FALSE) { # \dontrun{
boosterpak::upgrade_project(dry_run = TRUE)
boosterpak::upgrade_project()
} # }
```
