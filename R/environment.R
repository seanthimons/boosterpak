#' Restore a project without capability packs
#'
#' Restores the exact versions in `renv.lock`. Before restoration, normalizes
#' Posit Package Manager Linux URLs in the lockfile and removes Linux Platform
#' tags. Package versions and non-PPM repositories are preserved. No
#' `boosters.toml`, packs, or attachment hooks are required or created.
#' Public P3M repositories use Cloud CRAN as a binary fallback. Explicit
#' private overrides, repository dates, and repository opt-outs are preserved.
#'
#' @param root Project root containing `renv.lock`.
#' @return The restored package records, invisibly.
#' @export
restore_project <- function(root = ".") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(root, "renv.lock"))) {
    cli::cli_abort(
      "{.file renv.lock} does not exist; cannot restore exact package versions."
    )
  }
  normalize_lockfile_platform(root)
  configure_boosterpak_repositories(verbose = FALSE)
  add_public_cran_fallback()
  invisible(call_renv_restore(root))
}

#' Save a portable project snapshot without capability packs
#'
#' Records the active project library using the project's renv snapshot type,
#' then normalizes Posit Package Manager Linux URLs and Linux Platform tags.
#' No `boosters.toml`, packs, or attachment hooks are required or created.
#' This records installed versions; use [restore_project()] on a new machine.
#'
#' @param root Project root with an active project-local renv library.
#' @return The snapshot result, invisibly.
#' @export
snapshot_project <- function(root = ".") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  ensure_project_renv(root)
  configure_boosterpak_repositories(verbose = FALSE)
  add_public_cran_fallback()
  configure_boosterpak_install_policy(verbose = FALSE)
  invisible(call_renv_snapshot(root))
}

#' Accept compatible platform tags used by archived PPM binaries
#'
#' Fedora's R uses a redhat vendor tag while PPM archives use pc. PPM's Sonoma
#' repository can also serve R 4.6 binaries built with the older Darwin 20 SDK.
#' Add those same-CPU/OS aliases without pretending the host is another OS.
#' Explicit pak platform settings are left alone. Restore the option on exit.
#'
#' @param envir Calling frame in which to register option restoration.
#' @param platform Detected platform, or NULL to ask pak.
#' @return NULL, invisibly.
#' @noRd
scope_binary_platforms <- function(envir = parent.frame(), platform = NULL) {
  if (
    (!is_glibc_linux() && !grepl("^darwin", R.version$os)) ||
      !uses_posit_package_manager(getOption("repos")) ||
      !is.null(getOption("pkg.platforms")) ||
      nzchar(Sys.getenv("PKG_PLATFORMS"))
  ) {
    return(invisible(NULL))
  }
  platform <- platform %||% pak::system_r_platform()
  alias <- if (grepl("-linux-gnu-", platform)) {
    sub("^([^-]+)-[^-]+-", "\\1-pc-", platform)
  } else if (
    grepl("-apple-darwin", platform) &&
      as.integer(sub(".*-darwin([0-9]+).*", "\\1", platform)) >= 23L
  ) {
    sub("-darwin[0-9]+.*", "-darwin20", platform)
  } else {
    platform
  }
  old <- options(pkg.platforms = unique(c(platform, alias, "source")))
  restore <- bquote(options(.(old)))
  do.call(on.exit, list(restore, add = TRUE), envir = envir)
  invisible(NULL)
}

#' Add a binary mirror fallback to environment-only public P3M restores
#'
#' Preserve explicit private mirrors, repository dates, custom fallback names,
#' and the existing repository-configuration opt-out.
#' @return NULL, invisibly.
#' @noRd
add_public_cran_fallback <- function() {
  if (!should_configure_repositories()) {
    return(invisible(NULL))
  }
  pattern <- sprintf(
    "^https?://(%s)/cran(/|$)",
    paste(escape_regex(ppm_default_hosts()), collapse = "|")
  )
  public_primary <- function(values) {
    primary <- if (any(names(values) == "CRAN")) {
      values["CRAN"]
    } else {
      head(values, 1L)
    }
    any(grepl(pattern, unname(primary)))
  }
  repos <- getOption("repos")
  override <- renv::config$repos.override()
  if (
    !public_primary(repos) || (!is.null(override) && !public_primary(override))
  ) {
    return(invisible(NULL))
  }
  if (!any(names(repos) == "CRAN_fallback")) {
    repos["CRAN_fallback"] <- "https://cloud.r-project.org"
  }
  override <- override %||% repos
  if (is.null(names(override)) && length(override) == 1L) {
    names(override) <- "CRAN"
  }
  if (!any(names(override) == "CRAN_fallback")) {
    override["CRAN_fallback"] <- "https://cloud.r-project.org"
  }
  options(repos = repos, renv.config.repos.override = override)
  invisible(NULL)
}
