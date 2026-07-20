#' Synchronize a boosterpak project
#'
#' @param mode `"apply"` installs packages declared by `boosters.toml` and
#'   writes `boosters/attach.R`; `"restore"` restores from `renv.lock`.
#' @param root Project root.
#' @param hydrate Whether additive apply mode should reuse packages from
#'   renv-discoverable local libraries before downloading with pak. Restore
#'   mode and active-library apply mode ignore this option.
#' @param verbose Whether to print routine summaries.
#' @param library Package-library strategy for apply mode: `"renv"` uses the
#'   project-local renv library, while `"active"` uses the first writable entry
#'   in `.libPaths()`. `NULL` uses `[settings].library`, defaulting to `"renv"`.
#' @return Resolved package names, invisibly.
#' @export
sync <- function(mode = c("apply", "restore"), root = ".", hydrate = TRUE, verbose = NULL, library = NULL) {
  check_verbose(verbose)
  mode <- match.arg(mode)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  if (identical(mode, "restore")) {
    return(sync_restore(root, verbose))
  }

  config <- read_config(root)
  validate_config(config, root)
  library <- resolve_library_strategy(library, config)
  ensure_package_library(root, library)
  materialize_config_packs(config, root)
  packages <- resolve_config_packages(config, root)
  install_specs <- resolve_config_install_specs(config, root)
  missing <- missing_packages(packages, root, library)
  if (isTRUE(hydrate) && identical(library, "renv")) {
    hydrate_via_renv(plain_missing_packages(packages, install_specs, missing), root)
    missing <- missing_packages(packages, root, library)
  }
  missing_specs <- install_specs[packages %in% missing]
  install_via(missing_specs, root, library)
  sync_functions(config, root)
  write_attach(root, verbose = FALSE)

  if (
    identical(library, "renv") &&
      isTRUE(config$settings$auto_snapshot %||% TRUE)
  ) {
    call_renv_snapshot(root, packages)
  }

  if (should_emit(verbose)) {
    cli::cli_alert_success("Synchronized {length(packages)} declared package{?s}.")
  }
  invisible(packages)
}

sync_restore <- function(root, verbose = NULL) {
  if (!file.exists(boosters_file(root))) {
    cli::cli_abort(c(
      "{.file boosters.toml} does not exist.",
      "i" = "For lockfile-only projects, call {.code renv::restore()} directly.",
      "i" = "For boosterpak projects, run {.code boosterpak::init()} first."
    ), call = NULL)
  }
  if (!file.exists(file.path(root, "renv.lock"))) {
    cli::cli_abort("{.file renv.lock} does not exist; cannot restore exact package versions.", call = NULL)
  }

  call_renv_restore(root)
  config <- read_config(root)
  validate_config(config, root)
  packages <- resolve_config_packages(config, root)
  warn_missing_lock_packages(packages, file.path(root, "renv.lock"))

  if (should_emit(verbose)) {
    cli::cli_alert_success("Restored from {.file renv.lock}.")
  }
  invisible(packages)
}

warn_missing_lock_packages <- function(packages, lockfile) {
  lock <- tryCatch(jsonlite::read_json(lockfile), error = function(err) NULL)
  if (is.null(lock) || is.null(lock$Packages)) {
    return(invisible(FALSE))
  }
  locked <- names(lock$Packages)
  missing <- setdiff(packages, locked)
  if (length(missing) > 0) {
    cli::cli_warn("Direct declared package{?s} absent from {.file renv.lock}: {missing}.")
  }
  invisible(TRUE)
}
