#' Initialize a boosterpak project
#'
#' @param root Project root.
#' @param renv Whether to initialize project-local renv: `"ask"`, `"yes"`, or `"no"`.
#' @param rprofile Whether to add the helper auto-source line to `.Rprofile`.
#' @param verbose Whether to print routine summaries.
#' @return Project setup paths, invisibly.
#' @export
init <- function(root = ".", renv = c("ask", "yes", "no"), rprofile = c("ask", "yes", "no"), verbose = NULL) {
  check_verbose(verbose)
  renv <- match.arg(renv)
  rprofile <- match.arg(rprofile)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  dir.create(project_packs_dir(root), recursive = TRUE, showWarnings = FALSE)

  config_path <- boosters_file(root)
  wrote_config <- FALSE
  if (!file.exists(config_path)) {
    write_default_config(root)
    wrote_config <- TRUE
  }

  if (isTRUE(read_config(root)$settings$air_toml) && !file.exists(file.path(root, "air.toml"))) {
    writeLines(c("# air formatter configuration", ""), file.path(root, "air.toml"), useBytes = TRUE)
  }

  if (!has_project_renv(root)) {
    handle_renv_init(root, renv)
  }

  changed_rprofile <- ensure_rprofile_line(root, rprofile)

  if (should_emit(verbose)) {
    if (wrote_config) cli::cli_alert_success("Wrote {.file boosters.toml}.")
    if (isTRUE(changed_rprofile)) cli::cli_alert_success("Updated {.file .Rprofile}.")
  }

  invisible(list(config = config_path, rprofile_changed = changed_rprofile))
}

handle_renv_init <- function(root, renv) {
  if (identical(renv, "no")) {
    return(invisible(FALSE))
  }
  if (identical(renv, "ask")) {
    if (!interactive()) {
      cli::cli_alert_info("No project-local renv found. Use {.code renv = 'yes'} to initialize one.")
      return(invisible(FALSE))
    }
    answer <- utils::menu(c("Yes", "No"), title = "Initialize project-local renv now?")
    if (!identical(answer, 1L)) {
      return(invisible(FALSE))
    }
  }
  call_renv_init(root)
  invisible(TRUE)
}
