#' Restore a project without capability packs
#'
#' Restores the exact versions in `renv.lock`. Before restoration, normalizes
#' Posit Package Manager Linux URLs in the lockfile and removes Linux Platform
#' tags. Package versions and non-PPM repositories are preserved. No
#' `boosters.toml`, packs, or attachment hooks are required or created.
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
  configure_boosterpak_install_policy(verbose = FALSE)
  invisible(call_renv_snapshot(root))
}
