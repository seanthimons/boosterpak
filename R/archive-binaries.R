#' Make archived P3M binaries visible to pak during an exact restore
#'
#' latest indexes only current versions. For a compiled CRAN pin absent from
#' the binary index, use its release history to find the last date before the
#' following release, when that pin could still be current. Add that snapshot
#' only for this restore; package versions and the shared lockfile stay fixed.
#' Explicit dated repositories and private mirrors are left alone.
#' @noRd
scope_archived_binary_repos <- function(records, envir = parent.frame()) {
  if (!should_configure_repositories()) {
    return(invisible(NULL))
  }
  repos <- getOption("repos")
  override <- renv::config$repos.override()
  primary <- function(values) {
    if ("CRAN" %in% names(values)) {
      unname(values["CRAN"])
    } else {
      unname(head(values, 1L))
    }
  }
  pattern <- sprintf(
    "^https?://(%s)/cran/(__linux__/[^/]+/)?latest/?$",
    paste(escape_regex(ppm_default_hosts()), collapse = "|")
  )
  if (
    !any(grepl(pattern, primary(repos))) ||
      (!is.null(override) && !any(grepl(pattern, primary(override))))
  ) {
    return(invisible(NULL))
  }
  compiled <- names(records)[vapply(
    records,
    function(record) {
      identical(record$Source, "Repository") &&
        any(record$Repository %in% c("CRAN", "RSPM", "PPM", "P3M")) &&
        identical(record$NeedsCompilation, "yes")
    },
    logical(1)
  )]
  if (!length(compiled)) {
    return(invisible(NULL))
  }
  rows <- pak::meta_list(compiled)
  if (!nrow(rows)) {
    pak::meta_update()
    rows <- pak::meta_list(compiled)
  }
  has_binary <- function(name, rows) {
    any(
      rows$package == name &
        rows$version == records[[name]]$Version &
        rows$platform != "source"
    )
  }
  missing <- compiled[!vapply(compiled, has_binary, logical(1), rows = rows)]
  dates <- unique(vapply(
    missing,
    function(name) {
      history <- pak::pkg_history(name)
      released <- as.Date(history$date)
      locked <- released[history$Version == records[[name]]$Version]
      later <- released[released > locked]
      if (length(locked) != 1L || !length(later)) {
        return(NA_character_)
      }
      as.character(min(later) - 1L)
    },
    character(1)
  ))
  dates <- dates[!is.na(dates)]
  if (!length(dates)) {
    return(invisible(NULL))
  }
  old <- options("repos", "renv.config.repos.override")
  do.call(on.exit, list(bquote(options(.(old))), add = TRUE), envir = envir)
  extra <- stats::setNames(
    vapply(
      dates,
      function(date) {
        ppm_binary_url(
          primary(repos),
          snapshot = date,
          rewrite = is_glibc_linux()
        )
      },
      character(1)
    ),
    paste0("P3M_archive_", gsub("-", "_", dates))
  )
  options(
    repos = c(repos, extra[!extra %in% repos]),
    renv.config.repos.override = c(
      override %||% repos,
      extra[!extra %in% (override %||% repos)]
    )
  )
  pak::meta_update()
  rows <- pak::meta_list(missing)
  found <- missing[vapply(missing, has_binary, logical(1), rows = rows)]
  if (length(found)) {
    cli::cli_inform(c(
      "i" = "Using dated P3M binaries for locked {.pkg {found}}."
    ))
  }
  invisible(NULL)
}

#' Refuse source installation for packages explicitly required as binaries
#' @noRd
check_required_binaries <- function(records, packages) {
  if (!length(packages)) {
    return(invisible(NULL))
  }
  absent <- setdiff(packages, names(records))
  if (length(absent)) {
    cli::cli_abort("Required binary {.pkg {absent}} is not in the lockfile.")
  }
  refs <- vapply(
    packages,
    function(name) {
      paste0(name, "@", records[[name]]$Version)
    },
    character(1)
  )
  plan <- pak::pkg_deps(refs)
  rows <- match(packages, plan$package)
  source <- packages[
    is.na(rows) | is.na(plan$platform[rows]) | plan$platform[rows] == "source"
  ]
  if (length(source)) {
    cli::cli_abort(c(
      "No compatible binary resolves for locked {.pkg {source}}.",
      i = "Restore stopped before installation; source compilation is disabled for these packages."
    ))
  }
  invisible(NULL)
}
