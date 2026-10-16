# Check Whether Package Manager Serves Binary Packages

Posit Package Manager silently serves source packages whenever it cannot
match a request to a binary, for example when the repository URL is
generic on an unrecognized Linux distribution or the R user agent is
missing. The install then compiles every package from source.

## Usage

``` r
check_binary_repos(repos = getOption("repos"), package = "cli", verbose = NULL)
```

## Arguments

- repos:

  Repository URLs to check. Defaults to `getOption("repos")`.
  Repositories that are not Posit Package Manager repositories,
  including self-hosted ones not listed in `BOOSTERPAK_PPM_REPO`,
  `BOOSTERPAK_PPM_HOSTS`, or `options(boosterpak.ppm_hosts = c(...))`,
  are skipped.

- package:

  A small package available from the repository, used as the probe.
  Defaults to `"cli"`.

- verbose:

  Whether to print routine per-repository results. Warnings are always
  signaled for repositories serving source, unreachable repositories,
  and responses that cannot be interpreted.

## Value

A data frame with one row per checked repository, invisibly. Columns are
`repo`, `name` (the repository name in `repos`), `package`, `version`,
`status` (the HTTP status of the final response), `package_type`
(`"binary"` or `"source"`), `binary_tag`, and `binary` (`TRUE` for
binaries, `FALSE` for source, `NA` when it could not be determined).

## Details

`check_binary_repos()` sends one `HEAD` request for `package` to each
Posit Package Manager repository in `repos`, using the current session's
`HTTPUserAgent`, and reports the `X-Package-Type` and
`X-Package-Binary-Tag` response headers. It warns for every repository
that serves source.

It also warns when `download.file.method` is `"curl"` and
`download.file.extra` has no `-L`. Package Manager serves packages
through a redirect that R's `"curl"` method does not follow on its own,
so installs would save the redirect page instead of the package, even
though this check passes: it uses libcurl directly and follows
redirects.

The check follows the Linux binary layout, where the repository URL
itself selects binaries, so it only runs on Linux; on other platforms it
returns an empty data frame. It needs network access: it downloads the
repository's package index with
[`utils::available.packages()`](https://rdrr.io/r/utils/available.packages.html)
to find the current version of `package`, then sends the `HEAD` request.
Nothing runs unless you call it.

## Examples

``` r
if (FALSE) { # \dontrun{
check_binary_repos()
} # }
```
