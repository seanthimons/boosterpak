#' Check Whether Package Manager Serves Binary Packages
#'
#' Posit Package Manager silently serves source packages whenever it cannot
#' match a request to a binary, for example when the repository URL is generic
#' on an unrecognized Linux distribution or the R user agent is missing. The
#' install then compiles every package from source.
#'
#' `check_binary_repos()` sends one `HEAD` request for `package` to each
#' Posit Package Manager repository in `repos`, using the current session's
#' `HTTPUserAgent`, and reports the `X-Package-Type` and `X-Package-Binary-Tag`
#' response headers. It warns for every repository that serves source.
#'
#' It also warns when `download.file.method` is `"curl"` and
#' `download.file.extra` has no `-L`. Package Manager serves packages through a
#' redirect that R's `"curl"` method does not follow on its own, so installs
#' would save the redirect page instead of the package, even though this check
#' passes: it uses libcurl directly and follows redirects.
#'
#' The check follows the Linux binary layout, where the repository URL itself
#' selects binaries, so it only runs on Linux; on other platforms it returns an
#' empty data frame. It needs network access: it downloads each repository's
#' package index with `utils::available.packages()` to find the current version
#' of `package`, then sends the `HEAD` request. Nothing runs unless you call it,
#' and nothing is installed.
#'
#' ## Pinned versions
#'
#' A project restores the versions pinned in `renv.lock`, not the current
#' versions. Package Manager only serves a binary for a version that exists in
#' the snapshot the URL points at, so a pin that is older or newer than the
#' repository's current version can still compile from source even when the
#' probe above passes. Pass `lockfile` to compare every repository-sourced pin
#' with the index of its repository, using one index download per repository
#' and no installs:
#'
#' - Repositories come from the lockfile's `R$Repositories`. Each pin is matched
#'   to one of them by its `Repository` field: first by repository name, then
#'   by URL with any trailing slash ignored. A value that is neither, such as
#'   `RSPM`, is matched to the lockfile's only Package Manager repository when
#'   there is exactly one. Pins that match no repository are not compared.
#' - On glibc Linux, with boosterpak's repository setup enabled (see
#'   `BOOSTERPAK_CONFIGURE_REPOSITORIES`), each generic Package Manager URL is
#'   checked as the Linux binary URL a restore on this machine would use, such
#'   as `<host>/cran/__linux__/manylinux_2_28/latest`. Otherwise the URL as
#'   recorded is checked, because that is what a restore uses. Distro URLs such
#'   as `<host>/cran/__linux__/noble/latest` are checked as they are.
#' - A pin is available as binary when its version equals the version in that
#'   index. Other pins, and pins missing from the index, are not available as
#'   binary. A pin that needs compilation is one whose package is marked
#'   `NeedsCompilation: yes` in the index. For a pin whose version differs from
#'   the index, that flag describes the current version, so it is an estimate.
#' - The result is warned about when any pin is not available as binary. The
#'   worst offenders, pins that need compilation first, are listed in the
#'   warning and in the `"lockfile"` attribute.
#' - `snapshot_dates` optionally compares the pins with dated snapshots that
#'   you name. Only those dates are requested. Nothing scans other dates.
#'
#' @param repos Repository URLs to check. Defaults to `getOption("repos")`.
#'   Repositories that are not Posit Package Manager repositories, including
#'   self-hosted ones not listed in `BOOSTERPAK_PPM_REPO`,
#'   `BOOSTERPAK_PPM_HOSTS`, or `options(boosterpak.ppm_hosts = c(...))`, are
#'   skipped. Cannot be combined with `lockfile`.
#' @param package A small package available from the repository, used as the
#'   probe. Defaults to `"cli"`.
#' @param verbose Whether to print routine per-repository results. Warnings
#'   are always signaled for repositories serving source, unreachable
#'   repositories, responses that cannot be interpreted, and lockfile pins that
#'   are not available as binary. The count of lockfile pins that were not
#'   compared is always reported.
#' @param lockfile Path to an `renv.lock`. When given, the repositories are the
#'   ones recorded in the lockfile, and the pins are compared with their
#'   indexes as described above.
#' @param snapshot_dates Optional dates in `"YYYY-MM-DD"` form, such as
#'   `"2026-10-14"`. For each date, the pins from each Package Manager
#'   repository in `lockfile` are compared with that dated snapshot. Requires
#'   `lockfile`.
#' @return A data frame with one row per checked repository, invisibly. Columns
#'   are `repo`, `name` (the repository name in `repos`), `package`, `version`,
#'   `status` (the HTTP status of the final response), `package_type`
#'   (`"binary"` or `"source"`), `binary_tag`, and `binary` (`TRUE` for
#'   binaries, `FALSE` for source, `NA` when it could not be determined).
#'
#'   With `lockfile`, the data frame also carries a `"lockfile"` attribute, a
#'   list with: `lockfile` (the path); `pins` (repository-sourced pins compared,
#'   `M`); `available` (`N`, pins available as binary); `unavailable`;
#'   `needs_compilation` (`K`, unavailable pins whose package needs compilation
#'   in the index); `not_in_index` (unavailable pins whose package is not in
#'   the index); `unchecked` (repository-sourced pins not compared: their
#'   repository is not a Package Manager repository, is not recorded in the
#'   lockfile, or its index could not be read); `repositories` (per-repository
#'   counts); `offenders` (one row per unavailable pin that needs compilation or
#'   is not in the index, with `repository`, `package`, `pinned`, `current` (the
#'   index version, `NA` when absent), `available`, and `needs_compilation`);
#'   and `snapshots` (counts per `snapshot_dates` entry, or `NULL` when none
#'   were given).
#'
#'   The `"lockfile"` attribute is set only when the check runs, which is on
#'   Linux. On other platforms the function returns an empty data frame without
#'   it. The attribute is present on every Linux run with `lockfile`, including
#'   Linux without glibc. The `__linux__` rewrite described above applies only
#'   on glibc Linux.
#' @examples
#' \dontrun{
#' check_binary_repos()
#' check_binary_repos(lockfile = "renv.lock")
#' check_binary_repos(lockfile = "renv.lock", snapshot_dates = "2026-10-14")
#' }
#' @export
check_binary_repos <- function(
  repos = NULL,
  package = "cli",
  verbose = NULL,
  lockfile = NULL,
  snapshot_dates = NULL
) {
  check_verbose(verbose)
  if (!is.character(package) || length(package) != 1 || is.na(package)) {
    cli::cli_abort("{.arg package} must be a single package name.", call = NULL)
  }
  if (!is.null(lockfile) && !is.null(repos)) {
    cli::cli_abort("Supply {.arg repos} or {.arg lockfile}, not both.", call = NULL)
  }
  if (!is.null(snapshot_dates) && is.null(lockfile)) {
    cli::cli_abort("{.arg snapshot_dates} needs {.arg lockfile}.", call = NULL)
  }
  lock <- if (is.null(lockfile)) NULL else read_lockfile_repos(lockfile)
  snapshot_dates <- check_snapshot_dates(snapshot_dates)
  emit <- should_emit(verbose)
  result <- binary_check_frame()

  if (!is_linux()) {
    if (emit) {
      cli::cli_inform(c(
        "i" = "The binary check only supports Linux, where the repository URL selects binaries.",
        " " = "Windows and macOS binaries use platform-specific paths."
      ))
    }
    return(invisible(result))
  }

  if (is.null(lock)) {
    repos <- repos %||% getOption("repos")
  } else {
    repos <- lock$repos
  }
  repos <- repos[is_ppm_repo(repos)]
  # Compare the URL a restore on this machine uses, not the generic one. The
  # rewrite only happens where boosterpak's setup applies it, so otherwise the
  # URL as recorded is probed, including for the dated snapshots.
  rewrite <- !is.null(lock) && should_configure_repositories() && is_glibc_linux()
  if (rewrite) {
    repos <- stats::setNames(ppm_binary_url(repos), names(repos))
  }
  if (length(repos) == 0 && is.null(lock)) {
    if (emit) {
      cli::cli_inform(c("i" = "No Posit Package Manager repositories are configured."))
    }
    return(invisible(result))
  }

  if (length(repos) > 0 && curl_lacks_redirect_flag()) {
    cli::cli_warn(c(
      "{.code download.file.method} is {.val curl} but {.code download.file.extra} has no {.code -L}, so installs from Package Manager save its redirect page instead of the package.",
      "i" = "Posit recommends {.code options(download.file.extra = \"-fsSL\")} for curl. Set it earlier in {.file .Rprofile} than the boosterpak block, which appends its user agent header after your flags.",
      "i" = "This check uses libcurl, which follows redirects, so it can pass while curl downloads fail."
    ))
  }

  repo_names <- names(repos) %||% rep("", length(repos))
  repo_names[is.na(repo_names)] <- ""
  checked <- Map(
    function(repo, name) check_binary_repo(repo, name, package, emit),
    unname(repos),
    repo_names
  )
  rows <- lapply(checked, `[[`, "row")
  if (length(rows) > 0) {
    result <- do.call(rbind, unname(rows))
  }

  if (!is.null(lock)) {
    summary <- lockfile_summary(
      lock,
      unname(repos),
      repo_names,
      checked,
      snapshot_dates,
      rewrite
    )
    summary$lockfile <- lockfile
    report_lockfile_summary(summary, emit)
    attr(result, "lockfile") <- summary
  }
  invisible(result)
}

#' Check Whether R Runs on Linux
#'
#' @return `TRUE` when R runs on Linux.
#' @noRd
is_linux <- function() {
  startsWith(R.version$os, "linux")
}

#' Check Whether the Curl Method Is Missing the Redirect Flag
#'
#' Package Manager answers package requests with a redirect, which R's `"curl"`
#' download method only follows when `download.file.extra` has `-L`.
#'
#' @param method The download method.
#' @param extra The extra arguments passed to the download program.
#' @return `TRUE` when `method` is `"curl"` and `extra` has neither a short
#'   flag cluster containing `L` (such as `-L` or `-fsSL`) nor `--location`.
#' @noRd
curl_lacks_redirect_flag <- function(
  method = getOption("download.file.method"),
  extra = getOption("download.file.extra")
) {
  if (!identical(method, "curl")) {
    return(FALSE)
  }
  extra <- paste(extra, collapse = " ")
  !grepl(
    "(^|\\s)(--location(-trusted)?|-[A-Za-z0-9]*L[A-Za-z0-9]*)(?=\\s|$)",
    extra,
    perl = TRUE
  )
}

#' Create an Empty Binary Check Result
#'
#' @return A zero-row data frame with the binary check columns.
#' @noRd
binary_check_frame <- function(
  repo = character(),
  name = character(),
  package = character(),
  version = character(),
  status = integer(),
  package_type = character(),
  binary_tag = character(),
  binary = logical()
) {
  data.frame(
    repo = repo,
    name = name,
    package = package,
    version = version,
    status = status,
    package_type = package_type,
    binary_tag = binary_tag,
    binary = binary,
    stringsAsFactors = FALSE
  )
}

#' Check One Repository for Binary Packages
#'
#' Reads the repository index once, then uses it for the probe and returns it
#' so a lockfile check can compare pins without another download.
#'
#' @param repo Repository URL.
#' @param name Repository name, or an empty string.
#' @param package Package used as the probe.
#' @param emit Whether to print routine results.
#' @return A list with `row`, a one-row binary check data frame, and `index`,
#'   the `available.packages()` matrix or `NULL` when the index could not be
#'   read.
#' @noRd
check_binary_repo <- function(repo, name, package, emit) {
  label <- if (nzchar(name)) paste0(name, " (", repo, ")") else repo
  contriburl <- utils::contrib.url(repo, type = "source")
  row <- function(version = NA_character_, status = NA_integer_, type = NA_character_, tag = NA_character_) {
    binary_check_frame(
      repo = repo,
      name = name,
      package = package,
      version = version,
      status = as.integer(status),
      package_type = type,
      binary_tag = tag,
      binary = if (is.na(type)) NA else identical(type, "binary")
    )
  }

  found <- fetch_package_index(contriburl)
  if (!is.null(found$error)) {
    cli::cli_warn(
      "{label}: could not read the package index ({found$error}), so binary support is unknown."
    )
    return(list(row = row(), index = NULL))
  }
  index <- found$index
  version <- index_version(index, package)
  if (is.na(version)) {
    if (emit) {
      cli::cli_alert_info("{label}: {.pkg {package}} is not in this repository.")
    }
    return(list(row = row(), index = index))
  }

  response <- fetch_package_headers(
    sprintf("%s/%s_%s.tar.gz", contriburl, package, version)
  )
  if (!is.null(response$error)) {
    cli::cli_warn(
      "{label}: the request for {.pkg {package}} {version} failed ({response$error}), so binary support is unknown."
    )
    return(list(row = row(version), index = index))
  }

  type <- unname(response$headers["x-package-type"])
  tag <- unname(response$headers["x-package-binary-tag"])
  result <- row(version, response$status, type, tag)

  if (!identical(response$status, 200L)) {
    cli::cli_warn(
      "{label}: the request for {.pkg {package}} {version} returned HTTP {response$status}."
    )
  } else if (is.na(type)) {
    cli::cli_warn(
      "{label}: the response has no {.field X-Package-Type} header, so binary support is unknown."
    )
  } else if (identical(type, "source")) {
    cli::cli_warn(c(
      "{label} is serving {.strong source} packages ({.pkg {package}} {version}), so installs compile from source.",
      "i" = source_hint(repo)
    ))
  } else if (!identical(type, "binary")) {
    cli::cli_warn(
      "{label}: the response has an unexpected {.field X-Package-Type} of {.val {type}}."
    )
  } else if (emit) {
    cli::cli_alert_success(
      "{label}: serving {.strong binary} packages ({.pkg {package}} {version}, {.field {tag}})."
    )
  }
  list(row = result, index = index)
}

#' Explain Why a Repository Serves Source
#'
#' @param repo A Package Manager repository URL.
#' @return A hint naming the likely fix.
#' @noRd
source_hint <- function(repo) {
  repo <- sub("/+$", "", repo)
  setup <- "{.code boosterpak::init()} sets this up on glibc Linux."
  agent <- paste(
    "check the R user agent: {.code options(HTTPUserAgent)}, and",
    "{.code options(download.file.extra)} for curl or wget."
  )
  if (grepl(ppm_manylinux_pattern(), repo, ignore.case = TRUE)) {
    return(paste("The URL already selects binaries, so", agent, setup))
  }
  linux <- sub(
    ppm_snapshot_pattern(),
    "\\1/__linux__/manylinux_2_28/\\3",
    repo,
    ignore.case = TRUE
  )
  if (identical(linux, repo)) {
    return(paste("Use a binary URL for your platform and an R user agent;", agent, setup))
  }
  paste(
    sprintf(
      "Use a manylinux URL such as {.url %s} together with an R user agent; %s",
      cli_escape(linux),
      agent
    ),
    setup
  )
}

#' Build the Linux Binary URL for Package Manager Repositories
#'
#' Rewrites a generic `<host>/<repo>/<latest|YYYY-MM-DD>` URL to the manylinux
#' binary URL for `snapshot`. A URL that already selects Linux binaries, such as
#' a manylinux or distro URL (`<host>/<repo>/__linux__/<distro>/<snapshot>`),
#' keeps its distro segment and only has its snapshot segment replaced. A
#' trailing slash is dropped. Other URLs are returned unchanged.
#'
#' With `rewrite = FALSE`, a generic URL is not given the `__linux__` segment:
#' only its snapshot segment changes, as for a distro URL.
#'
#' @param repo A character vector of repository URLs.
#' @param snapshot `NULL` to keep each URL's own snapshot, or a `"YYYY-MM-DD"`
#'   date to use instead. With a date, a Package Manager URL with no snapshot
#'   segment to replace gives `NA`, so the caller can skip it.
#' @param rewrite Whether a generic URL gets the manylinux binary segment.
#' @return `repo` with the same names, rewritten where it matches.
#' @noRd
ppm_binary_url <- function(repo, snapshot = NULL, rewrite = TRUE) {
  date <- "[0-9]{4}-[0-9]{2}-[0-9]{2}"
  generic <- sprintf("^(https?://(%s)/[^/]+)/(latest|%s)$", ppm_host_pattern(), date)
  linux <- sprintf(
    "^(https?://(%s)/[^/]+/__linux__/[^/]+)/(latest|%s)$",
    ppm_host_pattern(),
    date
  )
  repo <- sub("/+$", "", repo)
  to <- if (is.null(snapshot)) "\\3" else snapshot
  out <- repo
  generic_hit <- grepl(generic, repo, ignore.case = TRUE)
  linux_hit <- grepl(linux, repo, ignore.case = TRUE)
  binary_segment <- if (rewrite) "__linux__/manylinux_2_28/" else ""
  out[generic_hit] <- sub(
    generic,
    paste0("\\1/", binary_segment, to),
    repo[generic_hit],
    ignore.case = TRUE
  )
  out[linux_hit] <- sub(
    linux,
    paste0("\\1/", to),
    repo[linux_hit],
    ignore.case = TRUE
  )
  if (!is.null(snapshot)) {
    out[is_ppm_repo(repo) & !(generic_hit | linux_hit)] <- NA_character_
  }
  out
}

#' Escape Text for cli Messages
#'
#' cli reads `{...}` in a message as code, so text taken from a lockfile, such
#' as a package name, is escaped with doubled braces before it is used as a
#' message line.
#'
#' @param text A character vector.
#' @return `text` with every brace doubled.
#' @noRd
cli_escape <- function(text) {
  gsub("([{}])", "\\1\\1", text)
}

#' Read the Repositories and Repository-Sourced Pins of a Lockfile
#'
#' @param lockfile Path to an `renv` lockfile.
#' @return A list with `repos`, a named character vector of the repository URLs
#'   recorded in the lockfile (names are the repository names, or the URL when
#'   a repository has no name), and `pins`, a data frame with `package`,
#'   `version`, `repository` (the raw `Repository` field), and `resolved` (the
#'   name in `repos` the pin is matched to, `NA` when none) for every package
#'   whose `Repository` field is set.
#' @noRd
read_lockfile_repos <- function(lockfile) {
  if (!is.character(lockfile) || length(lockfile) != 1 || is.na(lockfile)) {
    cli::cli_abort("{.arg lockfile} must be a single file path.", call = NULL)
  }
  if (!file.exists(lockfile)) {
    cli::cli_abort("{.arg lockfile} {.file {lockfile}} does not exist.", call = NULL)
  }
  lock <- tryCatch(jsonlite::read_json(lockfile), error = function(err) NULL)
  if (is.null(lock) || is.null(lock$Packages)) {
    cli::cli_abort("{.file {lockfile}} is not a readable {.pkg renv} lockfile.", call = NULL)
  }

  recorded <- lock$R$Repositories %||% list()
  urls <- vapply(
    recorded,
    function(repo) as.character(repo$URL %||% NA_character_),
    character(1)
  )
  names <- vapply(
    recorded,
    function(repo) as.character(repo$Name %||% ""),
    character(1)
  )
  keep <- !is.na(urls) & nzchar(urls)
  urls <- urls[keep]
  names <- names[keep]
  # A repository without a name is known by its URL.
  names[!nzchar(names)] <- urls[!nzchar(names)]
  repos <- stats::setNames(urls, names)

  from_repo <- Filter(function(pin) !is.null(pin$Repository), lock$Packages)
  pins <- data.frame(
    package = vapply(from_repo, function(pin) as.character(pin$Package %||% NA_character_), character(1)),
    version = vapply(from_repo, function(pin) as.character(pin$Version %||% NA_character_), character(1)),
    repository = vapply(from_repo, function(pin) as.character(pin$Repository), character(1)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  pins$resolved <- resolve_pin_repositories(pins$repository, repos)
  list(repos = repos, pins = pins)
}

#' Match Pin Repository Fields to Recorded Repositories
#'
#' renv records the repository a package came from in its `Repository` field,
#' and that value is not always a repository name in `R$Repositories`. Each
#' value is matched by name first, then by URL with any trailing slash ignored.
#' A value that is neither, such as `RSPM` in a lockfile that records only
#' `CRAN`, is matched to the only recorded Package Manager repository, when
#' there is exactly one. A URL that is not recorded matches nothing.
#'
#' @param values The `Repository` field of each pin.
#' @param repos A named character vector of recorded repository URLs.
#' @return A character vector the length of `values`, with the matched name in
#'   `repos` or `NA` when no repository matches.
#' @noRd
resolve_pin_repositories <- function(values, repos) {
  recorded <- names(repos)
  urls <- sub("/+$", "", unname(repos))
  ppm <- names(repos)[is_ppm_repo(repos)]
  fallback <- if (length(ppm) == 1) ppm else NA_character_
  vapply(
    values,
    function(value) {
      if (is.na(value) || !nzchar(value)) {
        return(NA_character_)
      }
      if (value %in% recorded) {
        return(value)
      }
      trimmed <- sub("/+$", "", value)
      hit <- match(trimmed, urls)
      if (!is.na(hit)) {
        return(recorded[[hit]])
      }
      if (grepl("^[a-z][a-z0-9+.-]*://", value, ignore.case = TRUE)) {
        return(NA_character_)
      }
      fallback
    },
    character(1),
    USE.NAMES = FALSE
  )
}

#' Validate Snapshot Dates
#'
#' @param dates `NULL` or a character vector of `"YYYY-MM-DD"` dates.
#' @return A character vector of unique dates, empty when `dates` is `NULL`.
#' @noRd
check_snapshot_dates <- function(dates) {
  if (is.null(dates)) {
    return(character())
  }
  valid <- is.character(dates) &&
    !anyNA(dates) &&
    all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dates)) &&
    !anyNA(as.Date(dates, format = "%Y-%m-%d"))
  if (!valid) {
    cli::cli_abort(
      "{.arg snapshot_dates} must be dates in {.val YYYY-MM-DD} form.",
      call = NULL
    )
  }
  unique(dates)
}

#' Find the Current Version of a Package in an Index
#'
#' @param index An index as returned by `fetch_package_index()`.
#' @param package Package name.
#' @return The version in the index, or `NA` when the package is not listed.
#' @noRd
index_version <- function(index, package) {
  if (!package %in% rownames(index)) {
    return(NA_character_)
  }
  unname(index[package, "Version"])
}

#' Compare Pinned Versions With a Repository Index
#'
#' @param pins A data frame with `package` and `version` columns.
#' @param index An index as returned by `fetch_package_index()`.
#' @return A data frame with one row per pin: `package`, `pinned`, `current`
#'   (the index version, `NA` when absent), `available` (the pinned version is
#'   the index version), and `needs_compilation` (the index marks the package
#'   `yes`; `FALSE` when absent).
#' @noRd
compare_pins_to_index <- function(pins, index) {
  row <- match(pins$package, rownames(index))
  present <- !is.na(row)
  current <- rep(NA_character_, nrow(pins))
  current[present] <- index[row[present], "Version"]
  needs <- rep(FALSE, nrow(pins))
  if ("NeedsCompilation" %in% colnames(index)) {
    needs[present] <- index[row[present], "NeedsCompilation"] %in% "yes"
  }
  data.frame(
    package = pins$package,
    pinned = pins$version,
    current = current,
    available = !is.na(current) & !is.na(pins$version) & current == pins$version,
    needs_compilation = needs,
    stringsAsFactors = FALSE
  )
}

#' Summarize Lockfile Pins Against Their Repository Indexes
#'
#' @param lock A list from `read_lockfile_repos()`.
#' @param repos Binary repository URLs, one per checked repository.
#' @param repo_names Repository names matching `repos`.
#' @param checked Results of `check_binary_repo()`, matching `repos`.
#' @param dates Validated snapshot dates, possibly empty.
#' @param rewrite Whether generic Package Manager URLs are rewritten to the
#'   manylinux binary URL, as `check_binary_repos()` does for `repos`.
#' @return A list with the totals, `repositories`, `offenders`, and
#'   `snapshots` (`NULL` without dates) fields described for
#'   `check_binary_repos()`.
#' @noRd
lockfile_summary <- function(lock, repos, repo_names, checked, dates, rewrite = TRUE) {
  pins <- lock$pins
  repositories <- list()
  offenders <- list()
  for (i in seq_along(repos)) {
    index <- checked[[i]]$index
    if (is.null(index)) {
      next
    }
    mine <- pins[pins$resolved %in% repo_names[[i]], , drop = FALSE]
    comparison <- compare_pins_to_index(mine, index)
    unavailable <- !comparison$available
    absent <- is.na(comparison$current)
    repositories[[length(repositories) + 1]] <- data.frame(
      repository = repo_names[[i]],
      url = repos[[i]],
      pins = nrow(mine),
      available = sum(comparison$available),
      needs_compilation = sum(unavailable & comparison$needs_compilation),
      not_in_index = sum(absent),
      stringsAsFactors = FALSE
    )
    worst <- comparison[unavailable & (comparison$needs_compilation | absent), , drop = FALSE]
    offenders[[length(offenders) + 1]] <- data.frame(
      repository = rep(repo_names[[i]], nrow(worst)),
      package = worst$package,
      pinned = worst$pinned,
      current = worst$current,
      available = worst$available,
      needs_compilation = worst$needs_compilation,
      stringsAsFactors = FALSE
    )
  }

  repositories <- if (length(repositories) > 0) {
    do.call(rbind, repositories)
  } else {
    data.frame(
      repository = character(), url = character(), pins = integer(),
      available = integer(), needs_compilation = integer(),
      not_in_index = integer(), stringsAsFactors = FALSE
    )
  }
  offenders <- if (length(offenders) > 0) {
    offenders <- do.call(rbind, offenders)
    offenders[order(!offenders$needs_compilation, offenders$package), , drop = FALSE]
  } else {
    data.frame(
      repository = character(), package = character(), pinned = character(),
      current = character(), available = logical(),
      needs_compilation = logical(), stringsAsFactors = FALSE
    )
  }
  rownames(offenders) <- NULL

  checked_pins <- sum(repositories$pins)
  list(
    pins = checked_pins,
    available = sum(repositories$available),
    unavailable = checked_pins - sum(repositories$available),
    needs_compilation = sum(repositories$needs_compilation),
    not_in_index = sum(repositories$not_in_index),
    unchecked = nrow(pins) - checked_pins,
    repositories = repositories,
    offenders = offenders,
    snapshots = lockfile_snapshot_counts(lock, pins, dates, rewrite)
  )
}

#' Count Available Pins in User-Supplied Snapshots
#'
#' Requests one index per Package Manager repository and date in `dates`. Only
#' the dates given by the user are requested. The URLs follow the same rule as
#' the repositories in `check_binary_repos()`: with `rewrite` they are the
#' manylinux binary URLs, otherwise only the snapshot segment of the recorded
#' URL changes, so a snapshot row and the latest row compare the same URL form.
#'
#' @param lock A list from `read_lockfile_repos()`.
#' @param pins The repository-sourced pins from `lock`.
#' @param dates Validated snapshot dates, possibly empty.
#' @param rewrite Whether generic URLs are rewritten to the manylinux binary URL.
#' @return A data frame with `repository`, `date`, `pins`, and `available`, or
#'   `NULL` when `dates` is empty.
#' @noRd
lockfile_snapshot_counts <- function(lock, pins, dates, rewrite = TRUE) {
  if (length(dates) == 0) {
    return(NULL)
  }
  rows <- list()
  for (name in names(lock$repos)[is_ppm_repo(lock$repos)]) {
    mine <- pins[pins$resolved %in% name, , drop = FALSE]
    if (nrow(mine) == 0) {
      next
    }
    base <- unname(lock$repos[name])
    # Whether a URL can name a snapshot does not depend on the date.
    if (is.na(ppm_binary_url(base, snapshot = dates[[1]], rewrite = rewrite))) {
      cli::cli_warn(
        "{name}: the repository URL has no snapshot segment to change, so its snapshots are not compared."
      )
      next
    }
    for (date in dates) {
      url <- ppm_binary_url(base, snapshot = date, rewrite = rewrite)
      found <- fetch_package_index(utils::contrib.url(url, type = "source"))
      if (!is.null(found$error)) {
        cli::cli_warn(
          "{name} ({date}): could not read the package index ({found$error}), so the snapshot is not compared."
        )
        next
      }
      rows[[length(rows) + 1]] <- data.frame(
        repository = name,
        date = date,
        pins = nrow(mine),
        available = sum(compare_pins_to_index(mine, found$index)$available),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    return(data.frame(
      repository = character(), date = character(), pins = integer(),
      available = integer(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

#' Report the Lockfile Summary
#'
#' Warns when any pin is not available as binary, because a restore compiles
#' those pins. Otherwise reports success when `emit` is `TRUE`. The count of
#' pins not compared is always reported, whatever `emit` is.
#'
#' Text from the lockfile, such as package names and repository names, is
#' escaped before it reaches cli, so braces in it are shown rather than
#' evaluated.
#'
#' @param summary A list from `lockfile_summary()`, with `lockfile` added.
#' @param emit Whether to print routine results.
#' @return `summary`, invisibly.
#' @noRd
report_lockfile_summary <- function(summary, emit) {
  if (summary$pins == 0) {
    if (emit) {
      cli::cli_inform(c(
        "i" = "No pins in {.file {summary$lockfile}} come from Package Manager repositories, so there is nothing to compare."
      ))
    }
  } else {
    headline <- sprintf(
      "%d of %d pins available as binary; %d not available as binary, %d of them need compilation if not.",
      summary$available,
      summary$pins,
      summary$unavailable,
      summary$needs_compilation
    )
    if (summary$unavailable > 0) {
      offenders <- summary$offenders
      listing <- character()
      if (nrow(offenders) > 0) {
        worst <- utils::head(offenders, 10)
        bullets <- ifelse(
          is.na(worst$current),
          sprintf("%s %s (not in the index)", worst$package, worst$pinned),
          sprintf("%s %s (index: %s)", worst$package, worst$pinned, worst$current)
        )
        listing <- c(
          "i" = "These pins install from source instead of binaries. Worst offenders, compiled packages first:",
          stats::setNames(cli_escape(bullets), rep("*", length(bullets)))
        )
        more <- nrow(offenders) - nrow(worst)
        if (more > 0) {
          listing <- c(listing, "*" = sprintf("and %d more", more))
        }
      }
      cli::cli_warn(c(
        "{.file {summary$lockfile}}: {headline}",
        listing,
        "i" = "Options: relax the pins with {.code renv::update()}, point the lockfile repository at a dated snapshot (see {.arg snapshot_dates}), or accept compiling."
      ))
    } else if (emit) {
      cli::cli_alert_success("{.file {summary$lockfile}}: {headline}")
    }

    snapshots <- summary$snapshots
    if (emit && !is.null(snapshots) && nrow(snapshots) > 0) {
      # Each repository has its own snapshots, so the best date is chosen
      # within each repository rather than across all of them. A repository
      # gets one "(best)" mark, on its first date (in the order given) that
      # reaches its top count, and only when that count is above zero.
      best <- rep("", nrow(snapshots))
      for (repository in unique(snapshots$repository)) {
        rows <- which(snapshots$repository == repository)
        top <- max(snapshots$available[rows])
        if (top > 0) {
          best[[rows[which(snapshots$available[rows] == top)[[1]]]]] <- " (best)"
        }
      }
      lines <- sprintf(
        "%s %s: %d of %d pins available as binary%s",
        snapshots$repository,
        snapshots$date,
        snapshots$available,
        snapshots$pins,
        best
      )
      cli::cli_inform(c(
        "i" = "Exact pins available per snapshot date:",
        stats::setNames(cli_escape(lines), rep("*", length(lines)))
      ))
    }
  }

  if (summary$unchecked > 0) {
    cli::cli_inform(c(
      "i" = "{summary$unchecked} repository pin{?s} not compared: the repository is not a Package Manager repository, is not recorded in the lockfile, or its index could not be read."
    ))
  }
  invisible(summary)
}

#' Find the Current Version of a Package in a Repository
#'
#' Reads the repository index with `utils::available.packages()`, using the
#' session's `HTTPUserAgent`. The index lists one row per package with its
#' current `Version` and `NeedsCompilation`.
#'
#' @param contriburl A source `contrib` URL.
#' @return A list with `index`, the matrix returned by
#'   `available.packages()` (`NULL` when the index could not be read), and
#'   `error`, a message when the package index could not be read and `NULL`
#'   otherwise.
#' @noRd
fetch_package_index <- function(contriburl) {
  problems <- character()
  available <- tryCatch(
    withCallingHandlers(
      utils::available.packages(contriburl = contriburl, filters = list()),
      warning = function(cnd) {
        problems <<- c(problems, conditionMessage(cnd))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(cnd) {
      problems <<- c(problems, conditionMessage(cnd))
      NULL
    }
  )
  if (is.null(available) || nrow(available) == 0) {
    return(list(
      index = NULL,
      error = if (length(problems) > 0) {
        problems[[length(problems)]]
      } else {
        "the repository lists no packages"
      }
    ))
  }
  list(index = available, error = NULL)
}

#' Send a HEAD Request for a Package Tarball
#'
#' `curlGetHeaders()` sends `HTTPUserAgent` as the user agent and follows
#' redirects.
#'
#' @param url Package tarball URL.
#' @return A list with the final HTTP `status` and the lowercase-named response
#'   `headers`, or a list with an `error` message if the request failed.
#' @noRd
fetch_package_headers <- function(url) {
  lines <- tryCatch(
    curlGetHeaders(url, redirect = TRUE, timeout = 10L),
    error = function(cnd) cnd
  )
  if (inherits(lines, "error")) {
    return(list(error = conditionMessage(lines)))
  }
  list(
    status = as.integer(attr(lines, "status")),
    headers = parse_response_headers(lines)
  )
}

#' Parse the Final Response Headers
#'
#' With redirects, `curlGetHeaders()` returns the headers of every response in
#' order, so only the last block describes the final response.
#'
#' @param lines Header lines as returned by `curlGetHeaders()`.
#' @return A character vector of header values named by lowercase header name.
#' @noRd
parse_response_headers <- function(lines) {
  starts <- grep("^HTTP/", lines)
  if (length(starts) == 0) {
    return(character())
  }
  lines <- trimws(lines[-seq_len(max(starts))])
  lines <- lines[grepl(":", lines, fixed = TRUE)]
  stats::setNames(
    trimws(sub("^[^:]*:", "", lines)),
    tolower(trimws(sub(":.*$", "", lines)))
  )
}
