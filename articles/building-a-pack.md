# Building your own pack

A pack is a TOML manifest plus, optionally, a folder of helper-function
sidecar files. This vignette covers the manifest schema, the two on-disk
layouts, and the exact rules for `on_add` hooks — including the cases
where hooks deliberately do not run.

## Two layouts

A pack that only declares packages is a single flat file:

    packs/plotting.toml

A pack that carries helper functions or hooks must use the nested
layout, with sidecar files in a `functions/` directory next to the
manifest:

    packs/scaffold-analysis/scaffold-analysis.toml
    packs/scaffold-analysis/functions/fn_scaffold_analysis.R

The manifest file name, the directory name, and the `name` field must
all match. Declaring `functions` or `[hooks]` in a flat pack is a
validation error.

## Manifest schema

``` toml
name = "scaffold-analysis"
description = "Create a compact analysis project folder scaffold."
packages = ["fs", "here"]
functions = ["scaffold_analysis"]

[hooks]
on_add = ["scaffold_analysis"]
```

Required fields:

- `name` — must equal the manifest file name (without `.toml`).
- `description` — a one-line string.
- `packages` — always required, even if empty (`packages = []`).

Optional fields:

- `[sources]` — per-package install specs
  (e.g. `"ggtext" = "wilkelab/ggtext"`) for packages that should not
  install by plain CRAN name.
- `attach` — startup attachment intent: omit or `true` to attach the
  pack’s `packages`, `false` to install without attaching, or a
  character vector to attach a subset.
- `extends` — names of other packs this pack builds on; their packages,
  functions, and hooks resolve transitively.
- `functions` — helper functions the pack ships. Every listed name must
  have a matching `functions/fn_<name>.R` sidecar file.
- `[hooks]` with `on_add` — functions to run automatically after the
  pack is first added to a project.
- `[settings]` — default values for pack settings the project can
  override; see “Pack settings” below.

Each `fn_<name>.R` sidecar is copied into the project’s `boosters/`
folder by
[`add_pack()`](https://seanthimons.github.io/boosterpak/reference/add_pack.md)
and sourced into the global environment at startup via the `.Rprofile`
hook. Sidecars are ordinary R files: they should define the function (or
object) they are named after and nothing else surprising, since they are
sourced in every session.

## On-add hooks

`on_add` turns a pack from “install these things” into “set this project
up”. When the `scaffold-analysis` pack is added, boosterpak copies and
sources `fn_scaffold_analysis.R`, then calls `scaffold_analysis()`,
which builds the analysis folder tree.

The rules, precisely:

- **Hooks run once, on a genuinely new add.** A hook fires only when the
  pack was not already listed in `[packs].declared`. Re-adding a
  declared pack does nothing.
- **Hooks require `sync = TRUE`** (the default).
  `add_pack(name, sync = FALSE)` declares the pack and copies its
  functions but skips the hook entirely — there is no later catch-up.
- **[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
  never runs hooks.** Syncing rematerializes missing function files and
  installs packages, but it will not re-run (or first-run) any `on_add`
  hook. If you skipped the hook at add time, call the function yourself.
- **Hooks are called with no arguments.** Any configuration must live in
  the function’s own defaults. If you need different behavior (say, a
  different folder list for `scaffold_analysis()`), edit the sidecar
  file in your pack — the pack’s copy is the source of truth.
- **Hooks run from the project root.** boosterpak temporarily sets the
  working directory to the project root, so relative paths in a hook
  resolve against the project, not wherever you happened to call
  [`add_pack()`](https://seanthimons.github.io/boosterpak/reference/add_pack.md)
  from.
- **A hook must be one of the pack’s own functions.** Validation rejects
  a manifest whose `on_add` names anything not listed in `functions`,
  and the hook is looked up in the global environment after sourcing — a
  pack cannot run code it does not ship.
- **Ordering:** functions are copied and sourced first, then
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
  installs packages, then hooks run. A hook can therefore rely on the
  pack’s packages being installed, but it should still guard with
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html) for a
  clear error if installation was skipped.
- **GitHub packs behave identically.**
  [`add_github_pack()`](https://seanthimons.github.io/boosterpak/reference/add_github_pack.md)
  runs `on_add` hooks under the same conditions: new add plus
  `sync = TRUE`.

The common surprise is the second rule: if you add a pack with
`sync = FALSE`, or the pack name was already declared in `boosters.toml`
(for example after hand-editing the file or cloning a project), the hook
never fires. In a cloned project that is intentional —
[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
restores the environment without re-running project-scaffolding side
effects.

## Pack settings

Hooks take no arguments, so a `[settings]` table is how a pack exposes
knobs that vary per project. The pack declares defaults:

``` toml
name = "targets-curation"
description = "Scaffold a targets-based curation pipeline."
packages = ["targets", "tarchetypes", "cli"]
functions = ["scaffold_targets_curation"]

[settings]
dirs = ["data/raw", "data/processed", "R"]

[hooks]
on_add = ["scaffold_targets_curation"]
```

The first time the pack is added to a project, those defaults are copied
into a `[settings.packs.<name>]` section appended to `boosters.toml`
(packs pulled in via `extends` get their own sections too):

``` toml
[settings.packs.targets-curation]
dirs = ["data/raw", "data/processed", "R"]
```

Edit that section freely — it is the per-project override. Sidecar
functions read the effective value with
[`pack_setting()`](https://seanthimons.github.io/boosterpak/reference/pack_setting.md),
which resolves project override → pack default → the `default` argument:

``` r
scaffold_targets_curation <- function(
  dirs = boosterpak::pack_setting(
    "targets-curation",
    "dirs",
    default = c("data/raw", "R")
  )
) {
  fs::dir_create(fs::path(getwd(), dirs))
}
```

The rules mirror `on_add` hooks:

- **Scaffolded once, never overwritten.** The section is appended only
  when its header is missing. Re-adding the pack,
  [`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md),
  and every other boosterpak write leave your edits alone — all writers
  that touch an existing `boosters.toml` either rewrite a single known
  line or append, so custom sections survive by construction.
- **First add only, but regardless of `sync`.** Unlike hooks,
  scaffolding also happens with `add_pack(name, sync = FALSE)`.
- **Values are loosely typed** — strings, booleans, numbers, or string
  arrays. The consuming function validates what it reads.
- **[`remove_pack()`](https://seanthimons.github.io/boosterpak/reference/remove_pack.md)
  keeps the section**, the same way it keeps edited `fn_*.R` files.
  Delete it by hand if you no longer want it.

## Where packs live

Packs resolve from three scopes, first match wins:

1.  **Project** — `boosters/packs/` in the project, created by
    [`save_pack()`](https://seanthimons.github.io/boosterpak/reference/save_pack.md).
2.  **User** — your boosterpak config directory, populated by
    [`promote_pack()`](https://seanthimons.github.io/boosterpak/reference/promote_pack.md),
    shared across your projects.
3.  **Built-in** — shipped with the package (`core`, `eda`,
    `scaffold-analysis`, `example`, `github-example`).

The usual authoring loop is: get a project working, `save_pack("name")`
to capture its resolved packages and helper functions as a project pack,
edit the generated manifest (add `attach`, `[sources]`, or `[hooks]` by
hand), then `promote_pack("name")` when it is worth reusing elsewhere.
See the [getting
started](https://seanthimons.github.io/boosterpak/articles/getting-started.md)
vignette for that workflow end-to-end.
