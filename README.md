# boosterpak

<img src="man/figures/boosterpak_hex.png" align="right" width="140" alt="boosterpak hex logo" />

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

## Typical Workflow

```mermaid
flowchart TD
  A[Start or clone project] --> B[Initialize boosterpak]
  B --> C[Add reusable intent]
  C --> D[Add packs]
  C --> E[Add helper functions]
  D --> F[Sync project]
  E --> F
  F --> G[Packages installed in renv]
  F --> H[Helper files copied into boosters]
  G --> I[Edit code and helper files]
  H --> I
  I --> J[Save a reusable pack]
  J --> K[Pack TOML plus function sidecar]
  K --> L[Promote to user scope]
  L --> M[Reuse in another project]
  M --> D
```

The usual loop is to initialize once, add packs and helper functions as project
intent, run `sync()`, then capture a useful baseline with `save_pack()`. Packs
can be package-only, or they can carry exact copied `boosters/fn_*.R` helper
files in a sidecar directory for reuse across projects.

## Add a Pack

```r
boosterpak::add_pack("example")
```

The built-in pack catalog contains:

- `core`: `fs`, `here`, `janitor`, `rio`, `tidyverse`, and `digest`.
- `example`: extends `core` and installs `cli`.
- `analysis-scaffold`: installs `fs` and `here` and carries a helper for a
  compact analysis folder scaffold.
- `github-example`: installs `ComptoxR` from `seanthimons/ComptoxR`.

Packs can mix ordinary CRAN package names with source-specific install specs.
Declare every package in `packages`, then add a `[sources]` entry only for
packages that should come from somewhere else:

```toml
name = "plotting"
description = "Plotting packages from CRAN and GitHub."
packages = ["ggplot2", "patchwork", "ggtext"]

[sources]
"ggtext" = "wilkelab/ggtext"
```

In this pack, `ggplot2` and `patchwork` install by package name, while `ggtext`
uses the GitHub source spec.

Pack mutation is additive. Removing a pack updates `boosters.toml` and
can run sync, but it does not uninstall packages.

## Capture and Reuse Packs

```r
boosterpak::save_pack("project_baseline")
boosterpak::promote_pack("project_baseline")
```

`save_pack()` writes a flat TOML snapshot of the currently resolved project
packages and, by default, the helper functions listed in `[functions].installed`.
Use `functions = "all"` to capture every `boosters/fn_*.R` file,
`functions = "none"` for a package-only pack, `from = "core"` to fork one
existing pack, or `scope = "user"` to write directly to the machine-wide user
pack directory. `promote_pack()` copies a project pack and its function sidecar
to user scope, and `demote_pack()` copies both back into a project.

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
