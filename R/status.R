#' Report boosterpak project status
#'
#' @param root Project root.
#' @param verbose Whether to print routine summaries.
#' @return A list describing project status, invisibly.
#' @export
status <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config_exists <- file.exists(boosters_file(root))
  valid <- FALSE
  packages <- character()
  packs <- character()
  if (config_exists) {
    config <- read_config(root)
    valid <- tryCatch({
      validate_config(config, root)
      TRUE
    }, error = function(err) FALSE)
    if (valid) {
      packages <- resolve_config_packages(config, root)
      packs <- config$packs$declared %||% character()
    }
  }
  out <- list(
    config_exists = config_exists,
    config_valid = valid,
    packs = packs,
    packages = packages,
    missing_packages = missing_packages(packages),
    renv_active = is_project_renv_active(root),
    lockfile_exists = file.exists(file.path(root, "renv.lock")),
    rprofile_hook = has_rprofile_line(root)
  )
  if (should_emit(verbose)) {
    cli::cli_h1("boosterpak status")
    cli::cli_li("boosters.toml: {if (out$config_exists) 'present' else 'missing'}")
    cli::cli_li("config valid: {out$config_valid}")
    cli::cli_li("renv active: {out$renv_active}")
    cli::cli_li("renv.lock: {if (out$lockfile_exists) 'present' else 'missing'}")
    cli::cli_li(".Rprofile hook: {out$rprofile_hook}")
  }
  invisible(out)
}
