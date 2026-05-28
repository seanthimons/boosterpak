# boosterpak

`boosterpak` is an R package for declaring project package intent in a
human-edited `boosters.toml` file. It resolves named "booster" packs from
project, user, and built-in scopes, installs missing packages with `pak`, and
uses `renv` for project-local libraries and lockfiles.

## Install

```r
pak::pkg_install("seanthimons/boosterpak")
```

## Start a Project

```r
boosterpak::init(renv = "yes", rprofile = "yes")
boosterpak::sync()
```

`init()` writes `boosters.toml`, creates `boosters/packs/`, optionally writes
`air.toml`, manages the `.Rprofile` helper-source line, and can initialize
project-local `renv`.

## Add a Pack

```r
boosterpak::add_pack("example")
```

The built-in pack catalog contains:

- `core`: `fs`, `here`, `janitor`, `rio`, `tidyverse`, and `digest`.
- `example`: extends `core` and installs `cli`.
- `github-example`: installs `ComptoxR` from `seanthimons/ComptoxR`.

Pack mutation is additive. Removing a pack updates `boosters.toml` and
can run sync, but it does not uninstall packages.

## Capture and Reuse Packs

```r
boosterpak::save_pack("project_baseline")
boosterpak::promote_pack("project_baseline")
```

`save_pack()` writes a flat TOML snapshot of the currently resolved project
packages. Use `from = "core"` to fork one existing pack, or `scope = "user"` to
write directly to the machine-wide user pack directory. `promote_pack()` copies a
project pack to user scope, and `demote_pack()` copies it back into a project.

## Restore from a Lockfile

```r
boosterpak::sync(mode = "restore")
```

`sync(mode = "apply")` treats `boosters.toml` as intent and `renv.lock` as
downstream output. `sync(mode = "restore")` is the explicit path for exact
lockfile restoration.

## Inspect Status

```r
boosterpak::status()
boosterpak::list_packs()
```

`status()` reports config validity, declared and resolved packs, package counts,
missing direct packages, function drift or missing materialized files, pack
catalog counts, `renv` state, lockfile presence, and the `.Rprofile` hook.

Current development includes function materialization, pack capture/promotion,
and broader project status reporting; pruning remains out of scope.
