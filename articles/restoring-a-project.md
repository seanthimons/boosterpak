# Restoring a project on a new machine

This vignette covers the clone path: a boosterpak project that already
works on one machine, freshly cloned from a git remote onto another. The
goal is to get from `git clone` to a working session without re-running
project setup.

The short version:

``` r

# In R, from the cloned project directory:
renv::restore()

# Restart R, then:
boosterpak::sync(mode = "restore")
boosterpak::status()
```

Do not re-run
[`init()`](https://seanthimons.github.io/boosterpak/reference/init.md).
The project is already initialized;
[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
is the restore verb.

## What travels with the repo

A boosterpak project commits its intent and its lockfile, not its
installed environment. A clone brings:

- `boosters.toml`, the project control file.
- `boosters/packs/`, the project-local pack sidecars.
- `boosters/fn_*.R`, materialized helper functions, including any local
  edits.
- `boosters/attach.R`, the managed startup attachment file.
- `renv.lock`, the exact package versions.
- `.Rprofile` with the renv activation line and the boosterpak startup
  hook.
- `renv/activate.R`, the renv bootstrap script.

A clone does not bring:

- The renv project library. Packages must be reinstalled.
- The machine-wide user pack directory. Packs promoted with
  [`promote_pack()`](https://seanthimons.github.io/boosterpak/reference/promote_pack.md)
  live outside the repo, but the project does not need them to restore:
  [`add_pack()`](https://seanthimons.github.io/boosterpak/reference/add_pack.md)
  already materialized every declared pack into `boosters/packs/`.

## 1. Install R and open the project

Install R on the new machine, ideally the version recorded in the `"R"`
field of `renv.lock`. Then start R in the cloned project directory. The
committed `.Rprofile` sources `renv/activate.R`, which bootstraps renv
into an empty project library automatically.

The first startup may print errors from the boosterpak hook: `.Rprofile`
sources `boosters/attach.R`, whose
[`library()`](https://rdrr.io/r/base/library.html) calls refer to
packages that are not installed yet. These errors disappear after
restore and are harmless to the restore itself — but an error in
`.Rprofile` stops the rest of the file from running, so any custom
settings placed after the boosterpak hook will not apply until the
packages are restored.

## 2. Restore the library from the lockfile

`boosterpak` itself is not installed on this machine yet, so nothing
boosterpak-shaped can run first. Restore through renv, which installs
everything in the lockfile, including `boosterpak`.
[`init()`](https://seanthimons.github.io/boosterpak/reference/init.md)
snapshots `renv`, `pak`, and `boosterpak` into the lockfile (unless
`settings.auto_snapshot` is disabled) precisely so that a clone can
bootstrap this way.

``` r

renv::restore()
```

## 3. Reconcile the boosterpak layer

Restart R so the freshly restored packages and the startup hook load
cleanly, then run restore mode:

``` r

boosterpak::sync(mode = "restore")
```

Restore mode requires both `boosters.toml` and `renv.lock`, calls
[`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html),
validates the project config, and warns if direct declared packages are
absent from the lockfile. It is lockfile-exact: it does not hydrate from
local libraries, does not install anything beyond the lockfile, and does
not rewrite `boosters/attach.R` or helper files. Helper functions and
`attach.R` travel through git, so restore mode has nothing to
materialize; local edits to `boosters/fn_*.R` are preserved because they
are ordinary committed files.

## 4. Verify

``` r

boosterpak::status()
boosterpak::check_functions()
```

[`status()`](https://seanthimons.github.io/boosterpak/reference/status.md)
reports config validity, resolved packs and packages, missing direct
packages, attach state, function drift, renv state, lockfile presence,
and the `.Rprofile` hook.
[`check_functions()`](https://seanthimons.github.io/boosterpak/reference/check_functions.md)
compares materialized helper files against their pack sources.

## What does not re-run in a clone

- [`init()`](https://seanthimons.github.io/boosterpak/reference/init.md)
  side effects. The project already has `boosters.toml`, the `.Rprofile`
  hook, and renv infrastructure; there is nothing to initialize.
- Pack `on_add` hooks. Hooks fire when a pack is newly declared by
  [`add_pack()`](https://seanthimons.github.io/boosterpak/reference/add_pack.md).
  In a clone, every pack is already declared in `boosters.toml`, so
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
  restores the environment without re-running project-scaffolding side
  effects such as folder creation.

## Troubleshooting: boosterpak absent from the lockfile

Projects initialized with boosterpak 0.5, or with
`settings.auto_snapshot = false`, may not have `boosterpak` in
`renv.lock`, so
[`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html)
leaves it uninstalled. Bootstrap it once without relying on `boosterpak`
being loadable:

``` r

install.packages("renv")
renv::install(c("pak", "seanthimons/boosterpak"))
renv::snapshot(
  packages = c("renv", "pak", "boosterpak"),
  prompt = FALSE,
  update = TRUE
)
```

`update = TRUE` matters: without it, `renv::snapshot(packages = ...)`
rewrites the lockfile to contain only the listed packages and their
dependencies, dropping every other project package.

Then restart R and run `boosterpak::sync(mode = "restore")`.
