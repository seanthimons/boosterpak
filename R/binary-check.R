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
#' The check follows the Linux binary layout, where the repository URL itself
#' selects binaries, so it only runs on Linux; on other platforms it returns an
#' empty data frame. It needs network access: it downloads the repository's
#' package index with `utils::available.packages()` to find the current version
#' of `package`, then sends the `HEAD` request. Nothing runs unless you call it.
#'
#' @param repos Repository URLs to check. Defaults to `getOption("repos")`.
#'   Repositories that are not Posit Package Manager repositories, including
#'   self-hosted ones not listed in `BOOSTERPAK_PPM_REPO`,
#'   `BOOSTERPAK_PPM_HOSTS`, or `options(boosterpak.ppm_hosts = c(...))`, are
#'   skipped.
#' @param package A small package available from the repository, used as the
#'   probe. Defaults to `"cli"`.
#' @param verbose Whether to print routine per-repository results. Warnings
#'   are always signaled for repositories serving source, unreachable
#'   repositories, and responses that cannot be interpreted.
#' @return A data frame with one row per checked repository, invisibly. Columns
#'   are `repo`, `name` (the repository name in `repos`), `package`, `version`,
#'   `status` (the HTTP status of the final response), `package_type`
#'   (`"binary"` or `"source"`), `binary_tag`, and `binary` (`TRUE` for
#'   binaries, `FALSE` for source, `NA` when it could not be determined).
#' @examples
#' \dontrun{
#' check_binary_repos()
#' }
#' @export
check_binary_repos <- function(
  repos = getOption("repos"),
  package = "cli",
  verbose = NULL
) {
  check_verbose(verbose)
  if (!is.character(package) || length(package) != 1 || is.na(package)) {
    cli::cli_abort("{.arg package} must be a single package name.", call = NULL)
  }
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

  repos <- repos[is_ppm_repo(repos)]
  if (length(repos) == 0) {
    if (emit) {
      cli::cli_inform(c("i" = "No Posit Package Manager repositories are configured."))
    }
    return(invisible(result))
  }

  repo_names <- names(repos) %||% rep("", length(repos))
  repo_names[is.na(repo_names)] <- ""
  rows <- Map(
    function(repo, name) check_binary_repo(repo, name, package, emit),
    unname(repos),
    repo_names
  )
  invisible(do.call(rbind, unname(rows)))
}

#' Check Whether R Runs on Linux
#'
#' @return `TRUE` when R runs on Linux.
#' @noRd
is_linux <- function() {
  startsWith(R.version$os, "linux")
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
#' @param repo Repository URL.
#' @param name Repository name, or an empty string.
#' @param package Package used as the probe.
#' @param emit Whether to print routine results.
#' @return A one-row binary check data frame.
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

  found <- fetch_package_version(contriburl, package)
  if (!is.null(found$error)) {
    cli::cli_warn(
      "{label}: could not read the package index ({found$error}), so binary support is unknown."
    )
    return(row())
  }
  version <- found$version
  if (is.na(version)) {
    if (emit) {
      cli::cli_alert_info("{label}: {.pkg {package}} is not in this repository.")
    }
    return(row())
  }

  response <- fetch_package_headers(
    sprintf("%s/%s_%s.tar.gz", contriburl, package, version)
  )
  if (!is.null(response$error)) {
    cli::cli_warn(
      "{label}: the request for {.pkg {package}} {version} failed ({response$error}), so binary support is unknown."
    )
    return(row(version))
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
  result
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
  # The URL is data, so double its braces to keep cli from reading them.
  paste(
    sprintf(
      "Use a manylinux URL such as {.url %s} together with an R user agent; %s",
      gsub("([{}])", "\\1\\1", linux),
      agent
    ),
    setup
  )
}

#' Find the Current Version of a Package in a Repository
#'
#' @param contriburl A source `contrib` URL.
#' @param package Package name.
#' @return A list with `version` (`NA` when the repository does not contain
#'   `package`) and `error`, a message when the package index could not be read
#'   and `NULL` otherwise.
#' @noRd
fetch_package_version <- function(contriburl, package) {
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
      version = NA_character_,
      error = if (length(problems) > 0) {
        problems[[length(problems)]]
      } else {
        "the repository lists no packages"
      }
    ))
  }
  if (!package %in% rownames(available)) {
    return(list(version = NA_character_, error = NULL))
  }
  list(version = unname(available[package, "Version"]), error = NULL)
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
