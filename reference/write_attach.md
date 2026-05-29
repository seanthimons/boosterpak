# Write startup package attachment calls

Resolves package attach intent from `boosters.toml` and writes a managed
`boosters/attach.R` file containing static
[`library()`](https://rdrr.io/r/base/library.html) calls. Installation
intent remains controlled by pack `packages`; attachment controls only
what is loaded at startup by the optional `.Rprofile` hook.

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
