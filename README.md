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

The v0.1 built-in pack catalog contains:

- `core`: a minimal baseline pack.
- `example`: extends `core` and installs `cli`.
- `github-example`: demonstrates source override structure.

Pack mutation is additive in v0.1. Removing a pack updates `boosters.toml` and
can run sync, but it does not uninstall packages.

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

Phase 1 intentionally excludes function materialization, `save_pack()`, pack
promotion, and pruning.
