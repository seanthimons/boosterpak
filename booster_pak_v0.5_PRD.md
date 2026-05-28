# boosterpak v0.5 PRD: Portable Booster Packs with Functions

## Summary

Booster packs become the portable unit for both package declarations and user-customized helper files. Existing package-only packs remain valid, while packs may optionally declare helper functions and carry exact copied `fn_*.R` files in a sidecar directory.

## Pack Format

Pack TOML supports an optional top-level `functions` array:

```toml
name = "my_pack"
description = "Portable project helpers."
packages = ["cli"]
functions = ["ni", "my_helper"]
```

Each listed function is stored as an exact source file beside the pack:

- Project pack: `boosters/packs/my_pack.toml`
- Project sidecar: `boosters/packs/my_pack/functions/fn_ni.R`
- User pack: `<user_config>/packs/my_pack.toml`
- User sidecar: `<user_config>/packs/my_pack/functions/fn_ni.R`

Function names are derived from `fn_<name>.R`; the TOML stores only `<name>`.

## User Workflows

`save_pack()` captures packages and, by default, installed helper functions:

- `functions = "installed"` captures `[functions].installed`.
- `functions = "all"` captures every current `boosters/fn_*.R` file.
- `functions = "none"` writes a package-only pack.
- A character vector captures those exact function names.

Requested function files must exist in `boosters/`; missing files abort.

`add_pack()` remains the primary apply verb. It declares the pack in `boosters.toml`, materializes pack TOML and sidecar files into `boosters/packs/`, and copies bundled functions into root `boosters/fn_*.R`. Existing function files are preserved by default; callers must opt into overwrite behavior.

`sync()` reconciles declared packs by copying missing bundled functions and never overwriting edited local function files.

`promote_pack()` and `demote_pack()` copy both the TOML file and the sidecar directory.

`remove_pack(remove_functions = FALSE)` keeps copied function files by default. With `remove_functions = TRUE`, it deletes only unchanged files that exactly match the pack-provided sidecar copy and are not still provided by another declared pack.

## Out of Scope

External GitHub or URL function sourcing is not part of v0.5. Function files are portable artifacts, not patches, hashes, inline TOML strings, or external repository pointers.
