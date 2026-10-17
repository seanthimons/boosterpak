# Write startup package attachment calls

Resolves package attach intent from `boosters.toml` and writes a managed
`boosters/attach.R` file. The file attaches each package independently:
a package that is not installed is reported in one summary line, and the
rest still attach. Installation intent remains controlled by pack
`packages`; attachment controls only what is loaded at startup by the
optional `.Rprofile` hook. Packages from packs with
`attach_mode = "interactive"` are attached only when
[`interactive()`](https://rdrr.io/r/base/interactive.html) is true, so
workers and non-interactive runs skip them.

## Usage

``` r
write_attach(root = ".", verbose = NULL)
```

## Arguments

- root:

  Project root.

- verbose:

  Whether to print routine summaries.

## Value

Path to `boosters/attach.R`, invisibly.
