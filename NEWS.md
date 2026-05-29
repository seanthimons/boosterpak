# boosterpak 0.6.0.9000

- Added `create_pack()` for guided pack authoring from declared package intent. It writes pack TOML, optional source specs, explicit attach intent, and an optional nested function-template sidecar without mutating `boosters.toml` or running `sync()`.
- `sync(mode = "apply")` now writes a managed `boosters/attach.R` file with static `library()` calls for startup attachment intent. Packs can declare `attach = true`, `attach = false`, or `attach = ["pkg"]`; missing `attach` attaches direct pack packages by default.
- New top-level `[attach]` config supports `enabled`, `declared`, and `exclude`. Workflow packages from `core` and `[extras]` are installed but not attached unless explicitly listed in `[attach].declared`.
- The recommended `.Rprofile` hook now sources `boosters/attach.R` before `boosters/fn_*.R` helper files, and `status()` reports attach state.

# boosterpak 0.5.0.9001

- `sync(mode = "apply")` and eager `add_pack()` now hydrate plain-name missing packages from renv-discoverable local libraries before falling back to `pak::pkg_install()`. Use `hydrate = FALSE` to skip local reuse; `sync(mode = "restore")` remains an exact lockfile restore path.

# boosterpak 0.5.0.9000

- `init(renv = "yes")` now initializes and loads `renv` without an immediate restart, installs the bootstrap workflow packages `pak`, `renv`, and `boosterpak` into the project library, and snapshots them when `auto_snapshot = true`.
- The built-in `core` pack is now minimal (`pak`, `renv`). The previous analysis-oriented package set is available as the new `eda` pack.
- Projects initialized with boosterpak 0.5 can recover by running:

  ```r
  install.packages("renv")
  renv::install(c("pak", "seanthimons/boosterpak"))
  renv::snapshot(packages = c("renv", "pak", "boosterpak"), prompt = FALSE)
  ```

  Then restart R and run `boosterpak::sync()`.
