# Initialize a boosterpak project

Initialize a boosterpak project

## Usage

``` r
init(
  root = ".",
  renv = c("ask", "yes", "no"),
  rprofile = c("ask", "yes", "no"),
  verbose = NULL
)
```

## Arguments

- root:

  Project root.

- renv:

  Whether to initialize project-local renv: `"ask"`, `"yes"`, or `"no"`.

- rprofile:

  Whether to add the helper auto-source line to `.Rprofile`.

- verbose:

  Whether to print routine summaries.

## Value

Project setup paths, invisibly.
