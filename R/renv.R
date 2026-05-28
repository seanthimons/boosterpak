is_project_renv_active <- function(root = ".") {
  renv_dir <- file.path(root, "renv")
  activate <- file.path(renv_dir, "activate.R")
  if (!dir.exists(renv_dir) || !file.exists(activate)) {
    return(FALSE)
  }
  lib <- renv::paths$library(project = root)
  any(normalizePath(.libPaths(), winslash = "/", mustWork = FALSE) ==
    normalizePath(lib, winslash = "/", mustWork = FALSE))
}

has_project_renv <- function(root = ".") {
  renv_dir <- file.path(root, "renv")
  activate <- file.path(renv_dir, "activate.R")
  dir.exists(renv_dir) && file.exists(activate)
}

ensure_project_renv <- function(root = ".") {
  if (!is_project_renv_active(root)) {
    cli::cli_abort(c(
      "No active project-local renv library was found.",
      "i" = "Run {.code boosterpak::init(renv = 'yes')} or {.code renv::init()}, then restart R in the project."
    ), call = NULL)
  }
  invisible(TRUE)
}

call_renv_init <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::init(bare = TRUE)
}

call_renv_load <- function(root = ".") {
  renv::load(project = root, quiet = TRUE)
}

call_renv_snapshot <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::snapshot(project = root, prompt = FALSE)
}

call_renv_restore <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::restore(project = root, prompt = FALSE)
}

install_via <- function(packages, root = ".") {
  if (length(packages) == 0) {
    return(invisible(character()))
  }
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  pak::pkg_install(packages)
  invisible(packages)
}

missing_packages <- function(packages) {
  packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
}
