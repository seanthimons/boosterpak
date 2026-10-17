# Check Whether Package Manager Serves Binary Packages

Posit Package Manager silently serves source packages whenever it cannot
match a request to a binary, for example when the repository URL is
generic on an unrecognized Linux distribution or the R user agent is
missing. The install then compiles every package from source.

## Usage

``` r
check_binary_repos(
  repos = NULL,
  package = "cli",
  verbose = NULL,
  lockfile = NULL,
  snapshot_dates = NULL
)
```

## Arguments

- repos:

  Repository URLs to check. Defaults to `getOption("repos")`.
  Repositories that are not Posit Package Manager repositories,
  including self-hosted ones not listed in `BOOSTERPAK_PPM_REPO`,
  `BOOSTERPAK_PPM_HOSTS`, or `options(boosterpak.ppm_hosts = c(...))`,
  are skipped. Cannot be combined with `lockfile`.

- package:

  A small package available from the repository, used as the probe.
  Defaults to `"cli"`.

- verbose:

  Whether to print routine per-repository results. Warnings are always
  signaled for repositories serving source, unreachable repositories,
  responses that cannot be interpreted, and lockfile pins that are not
  available as binary. The count of lockfile pins that were not compared
  is always reported.

- lockfile:

  Path to an `renv.lock`. When given, the repositories are the ones
  recorded in the lockfile, and the pins are compared with their indexes
  as described above.

- snapshot_dates:

  Optional dates in `"YYYY-MM-DD"` form, such as `"2026-10-14"`. For
  each date, the pins from each Package Manager repository in `lockfile`
  are compared with that dated snapshot. Requires `lockfile`.

## Value

A data frame with one row per checked repository, invisibly. Columns are
`repo`, `name` (the repository name in `repos`), `package`, `version`,
`status` (the HTTP status of the final response), `package_type`
(`"binary"` or `"source"`), `binary_tag`, and `binary` (`TRUE` for
binaries, `FALSE` for source, `NA` when it could not be determined).

With `lockfile`, the data frame also carries a `"lockfile"` attribute, a
list with: `lockfile` (the path); `pins` (repository-sourced pins
compared, `M`); `available` (`N`, pins available as binary);
`unavailable`; `needs_compilation` (`K`, unavailable pins whose package
needs compilation in the index); `not_in_index` (unavailable pins whose
package is not in the index); `unchecked` (repository-sourced pins not
compared: their repository is not a Package Manager repository, is not
recorded in the lockfile, or its index could not be read);
`repositories` (per-repository counts); `offenders` (one row per
unavailable pin that needs compilation or is not in the index, with
`repository`, `package`, `pinned`, `current` (the index version, `NA`
when absent), `available`, and `needs_compilation`); and `snapshots`
(counts per `snapshot_dates` entry, or `NULL` when none were given).

The `"lockfile"` attribute is set only when the check runs, which is on
Linux. On other platforms the function returns an empty data frame
without it. The attribute is present on every Linux run with `lockfile`,
including Linux without glibc. The `__linux__` rewrite described above
applies only on glibc Linux.

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
returns an empty data frame. It needs network access: it downloads each
repository's package index with
[`utils::available.packages()`](https://rdrr.io/r/utils/available.packages.html)
to find the current version of `package`, then sends the `HEAD` request.
Nothing runs unless you call it, and nothing is installed.

### Pinned versions

A project restores the versions pinned in `renv.lock`, not the current
versions. Package Manager only serves a binary for a version that exists
in the snapshot the URL points at, so a pin that is older or newer than
the repository's current version can still compile from source even when
the probe above passes. Pass `lockfile` to compare every
repository-sourced pin with the index of its repository, using one index
download per repository and no installs:

- Repositories come from the lockfile's `R$Repositories`. Each pin is
  matched to one of them by its `Repository` field: first by repository
  name, then by URL with any trailing slash ignored. A value that is
  neither, such as `RSPM`, is matched to the lockfile's only Package
  Manager repository when there is exactly one. Pins that match no
  repository are not compared.

- On glibc Linux, with boosterpak's repository setup enabled (see
  `BOOSTERPAK_CONFIGURE_REPOSITORIES`), each generic Package Manager URL
  is checked as the Linux binary URL a restore on this machine would
  use, such as `<host>/cran/__linux__/manylinux_2_28/latest`. Otherwise
  the URL as recorded is checked, because that is what a restore uses.
  Distro URLs such as `<host>/cran/__linux__/noble/latest` are checked
  as they are.

- A pin is available as binary when its version equals the version in
  that index. Other pins, and pins missing from the index, are not
  available as binary. A pin that needs compilation is one whose package
  is marked `NeedsCompilation: yes` in the index. For a pin whose
  version differs from the index, that flag describes the current
  version, so it is an estimate.

- The result is warned about when any pin is not available as binary.
  The worst offenders, pins that need compilation first, are listed in
  the warning and in the `"lockfile"` attribute.

- `snapshot_dates` optionally compares the pins with dated snapshots
  that you name. Only those dates are requested. Nothing scans other
  dates.

## Examples

``` r
if (FALSE) { # \dontrun{
check_binary_repos()
check_binary_repos(lockfile = "renv.lock")
check_binary_repos(lockfile = "renv.lock", snapshot_dates = "2026-10-14")
} # }
```
