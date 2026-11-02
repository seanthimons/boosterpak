# Save a portable project snapshot without capability packs

Records the active project library using the project's renv snapshot
type, then normalizes Posit Package Manager Linux URLs and Linux
Platform tags. No `boosters.toml`, packs, or attachment hooks are
required or created. This records installed versions; use
[`restore_project()`](https://seanthimons.github.io/boosterpak/reference/restore_project.md)
on a new machine.

## Usage

``` r
snapshot_project(root = ".")
```

## Arguments

- root:

  Project root with an active project-local renv library.

## Value

The snapshot result, invisibly.
